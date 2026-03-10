/**
 * auth-bootstrap
 *
 * Verifies a Firebase Phone Auth ID token, upserts the user in Supabase,
 * and optionally creates a household if a family_name is supplied.
 *
 * POST /functions/v1/auth-bootstrap
 * Header:  Authorization: Bearer <firebase_id_token>
 * Body:    { "family_name"?: "Sharma Family" }   ← optional
 *
 * Responses
 *   201  { user, household }   new user created
 *   200  { user, household }   existing user returned
 *   400  invalid request body / phone number missing
 *   401  invalid / expired Firebase token
 *   403  household suspended
 *   405  wrong method
 *   500  unexpected server error
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyFirebaseToken } from "../_shared/firebase.ts";

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

// Service role client — bypasses RLS, targets app schema, never leaks to the client.
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  {
    auth: { persistSession: false },
    db: { schema: "app" },
  },
);

const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID")!;

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

  // ── 1. Extract Firebase token ──────────────────────────────────────────
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

  // ── 3. Verify Firebase token ───────────────────────────────────────────
  let uid: string;
  let phoneNumber: string;
  try {
    const claims = await verifyFirebaseToken(idToken, FIREBASE_PROJECT_ID);
    uid = claims.uid;
    if (!claims.phone_number) {
      return json({ error: "Token does not contain a phone number" }, 400);
    }
    phoneNumber = claims.phone_number;
  } catch (err) {
    console.error("Firebase token verification failed:", err);
    return json({ error: "Invalid or expired token" }, 401);
  }

  // ── 4. Look up existing user ───────────────────────────────────────────
  try {
    const { data: existingUser, error: lookupErr } = await supabase
      .from("users")
      .select(USER_COLS)
      .eq("firebase_uid", uid)
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
        .insert({ name: familyName, admin_firebase_uid: uid })
        .select(HOUSEHOLD_COLS)
        .single();

      if (hErr) throw hErr;

      // Create admin user
      const { data: user, error: uErr } = await supabase
        .from("users")
        .insert({
          firebase_uid: uid,
          phone: phoneNumber,
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
      .insert({ firebase_uid: uid, phone: phoneNumber })
      .select(USER_COLS)
      .single();

    if (uErr) {
      // Handle race condition: another request created the user first.
      if (uErr.code === "23505") {
        const { data: raceUser } = await supabase
          .from("users")
          .select(USER_COLS)
          .eq("firebase_uid", uid)
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
