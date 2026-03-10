/**
 * auth-bootstrap
 *
 * Verifies a Supabase Auth JWT token, upserts the user in the database,
 * and optionally creates a household if a family_name is supplied.
 *
 * POST /functions/v1/auth-bootstrap
 * Header:  Authorization: Bearer <supabase_jwt_token>
 * Body:    { "family_name"?: "Sharma Family" }   ← optional
 *
 * Responses
 *   201  { user, household }   new user created
 *   200  { user, household }   existing user returned
 *   400  invalid request body
 *   401  invalid / expired Supabase token
 *   403  household suspended
 *   405  wrong method
 *   500  unexpected server error
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// Service role client — bypasses RLS, targets app schema
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  {
    auth: { persistSession: false },
    db: { schema: "app" },
  },
);

// Client for verifying JWT tokens
const supabaseClient = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_ANON_KEY")!,
  {
    auth: { persistSession: false },
  },
);

// ─── Selected columns returned to the client ───────────────────────────────
const USER_COLS =
  "id, firebase_uid, phone, role, household_id, display_name, notifications_enabled, voice_enabled, created_at";
const HOUSEHOLD_COLS = "id, name, admin_firebase_uid, plan, suspended, created_at";

// ───────────────────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  // CORS pre-flight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // ── 1. Extract Supabase JWT token ──────────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ error: "Missing or malformed Authorization header" }, 401);
  }
  const idToken = authHeader.slice(7).trim();

  // ── 2. Parse optional body ─────────────────────────────────────────────
  let familyName: string | undefined;
  const contentType = req.headers.get("Content-Type") ?? "";
  if (contentType.includes("application/json")) {
    try {
      const body = await req.json();
      if (body.family_name !== undefined) {
        const trimmed = String(body.family_name).trim();
        if (trimmed.length < 1 || trimmed.length > 50) {
          return json({ error: "family_name must be 1–50 characters" }, 400);
        }
        familyName = trimmed;
      }
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }
  }

  // ── 3. Verify Supabase JWT token and get user ─────────────────────────
  let supabaseUserId: string;
  let email: string;
  try {
    const { data: { user }, error } = await supabaseClient.auth.getUser(idToken);
    
    if (error || !user) {
      console.error("Supabase token verification failed:", error);
      return json({ error: "Invalid or expired token" }, 401);
    }
    
    supabaseUserId = user.id;
    email = user.email || "no-email@placeholder.com";
  } catch (err) {
    console.error("Supabase token verification failed:", err);
    return json({ error: "Invalid or expired token" }, 401);
  }

  // ── 4. Look up existing user ───────────────────────────────────────────
  try {
    const { data: existingUser, error: lookupErr } = await supabase
      .from("users")
      .select(USER_COLS)
      .eq("firebase_uid", supabaseUserId)
      .is("deleted_at", null)
      .maybeSingle();

    if (lookupErr) throw lookupErr;

    if (existingUser) {
      // Fetch household if linked
      let household = null;
      if (existingUser.household_id) {
        const { data: hh, error: hhErr } = await supabase
          .from("households")
          .select(HOUSEHOLD_COLS)
          .eq("id", existingUser.household_id)
          .is("deleted_at", null)
          .maybeSingle();

        if (hhErr) throw hhErr;
        household = hh;

        if (household?.suspended) {
          return json({ error: "Household is suspended" }, 403);
        }
      }

      return json({ user: existingUser, household }, 200);
    }

    // ── 5a. New user + family_name → create household + admin user ────────
    if (familyName) {
      // Create household
      const { data: household, error: hErr } = await supabase
        .from("households")
        .insert({ name: familyName, admin_firebase_uid: supabaseUserId })
        .select(HOUSEHOLD_COLS)
        .single();

      if (hErr) throw hErr;

      // Create admin user
      const { data: user, error: uErr } = await supabase
        .from("users")
        .insert({
          firebase_uid: supabaseUserId,
          phone: email,  // Store email in phone field for now
          household_id: household.id,
          role: "admin",
        })
        .select(USER_COLS)
        .single();

      if (uErr) {
        // Best-effort rollback — household has no members yet, safe to delete.
        await supabase.from("households").delete().eq("id", household.id);
        throw uErr;
      }

      return json({ user, household }, 201);
    }

    // ── 5b. New user, no family_name → create user without household ──────
    // Flutter will prompt: "Create Family" or "Join Family"
    const { data: user, error: uErr } = await supabase
      .from("users")
      .insert({ 
        firebase_uid: supabaseUserId, 
        phone: email  // Store email in phone field for now
      })
      .select(USER_COLS)
      .single();

    if (uErr) {
      // Handle race condition: another request created the user first.
      if (uErr.code === "23505") {
        const { data: raceUser } = await supabase
          .from("users")
          .select(USER_COLS)
          .eq("firebase_uid", supabaseUserId)
          .is("deleted_at", null)
          .maybeSingle();
        if (raceUser) return json({ user: raceUser, household: null }, 200);
      }
      throw uErr;
    }

    return json({ user, household: null }, 201);
  } catch (err) {
    console.error("auth-bootstrap error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});
