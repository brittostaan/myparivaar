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

// Service role client — bypasses RLS
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
  "id, firebase_uid, email, phone, role, household_id, display_name, first_name, last_name, date_of_birth, photo_url, notifications_enabled, voice_enabled, created_at";
const HOUSEHOLD_COLS = "id, name, admin_firebase_uid, owner_user_id, created_at";

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
    console.log("Verifying token...");
    const { data: { user }, error } = await supabaseClient.auth.getUser(idToken);
    
    if (error || !user) {
      console.error("Token verification failed - error:", error);
      console.error("Token verification failed - user:", user);
      return json({ error: `Token verification failed: ${error?.message || 'No user returned'}` }, 401);
    }
    
    console.log("Token verified successfully for user:", user.id);
    supabaseUserId = user.id;
    email = user.email || "no-email@placeholder.com";
  } catch (err) {
    console.error("Token verification exception:", err);
    return json({ error: `Token verification exception: ${err.message}` }, 401);
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
          .maybeSingle();

        if (hhErr) throw hhErr;
        household = hh;
      }

      return json({ user: existingUser, household }, 200);
    }

    // ── 5a. New user + family_name → create user first, then household ────────
    if (familyName) {
      // Create admin user first (without household)
      const { data: user, error: uErr } = await supabase
        .from("users")
        .insert({
          firebase_uid: supabaseUserId,
          email: email,
          role: "admin",
        })
        .select(USER_COLS)
        .single();

      if (uErr) throw uErr;

      // Create household and set canonical admin column.
      const { data: household, error: hErr } = await supabase
        .from("households")
        .insert({ name: familyName, admin_firebase_uid: supabaseUserId, owner_user_id: user.id })
        .select(HOUSEHOLD_COLS)
        .single();

      if (hErr) {
        // Best-effort rollback — delete user that was just created
        await supabase.from("users").delete().eq("id", user.id);
        throw hErr;
      }

      // Update user with household_id
      const { data: updatedUser, error: updateErr } = await supabase
        .from("users")
        .update({ household_id: household.id })
        .eq("id", user.id)
        .select(USER_COLS)
        .single();

      if (updateErr) throw updateErr;

      return json({ user: updatedUser, household }, 201);
    }

    // ── 5b. New user, no family_name → create user without household ──────
    // Flutter will prompt: "Create Family" or "Join Family"
    const { data: user, error: uErr } = await supabase
      .from("users")
      .insert({ 
        firebase_uid: supabaseUserId, 
        email: email
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
    const errorMessage = err.message || err.toString();
    console.error("Error details:", JSON.stringify(err, null, 2));
    return json({ error: `Database operation failed: ${errorMessage}` }, 500);
  }
});
