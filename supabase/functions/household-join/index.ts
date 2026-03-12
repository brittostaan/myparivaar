/**
 * household-join
 *
 * Attaches an authenticated user to a household using an invite code.
 * The invite must be pending, non-expired, and issued for the caller's phone number.
 *
 * POST /functions/v1/household-join
 * Header:  Authorization: Bearer <firebase_id_token>
 * Body:    { "invite_code": "ABCD1234" }
 *
 * Responses
 *   201  { user, household }   — joined successfully
 *   400  invalid input
 *   401  unauthenticated
 *   403  invite not for this phone / household suspended
 *   404  user not found / invite not found, expired, or already used
 *   405  wrong method
 *   409  user already belongs to a household / invite claimed in race
 *   422  household at capacity (max 8)
 *   500  server error
 *
 * Atomicity strategy (no stored procedure):
 *   1. UPDATE household_invites SET status='accepted' WHERE id=? AND status='pending' AND expires_at > now
 *      → returns null if another request already claimed it (race protection)
 *   2. UPDATE users SET household_id=?, role='member' WHERE id=? AND household_id IS NULL
 *      → returns null if user was attached concurrently (race protection)
 *   3. If step 2 fails or returns null → best-effort revert invite to 'pending'
 *
 * Tables used (app schema):
 *   app.users, app.households, app.household_invites
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyFirebaseToken } from "../_shared/firebase.ts";

// ── Constants ────────────────────────────────────────────────────────────────
const MAX_HOUSEHOLD_SIZE = 8;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

// ── Supabase (service role) ──────────────────────────────────────────────────
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  {
    auth: { persistSession: false },
    db: { schema: "app" },
  },
);

const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID")!;

// ── Helpers ──────────────────────────────────────────────────────────────────
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// Columns returned to the client — never expose internal fields
const USER_COLS =
  "id, firebase_uid, phone, role, household_id, display_name, notifications_enabled, voice_enabled, created_at";
const HOUSEHOLD_COLS = "id, name, plan, suspended, created_at";

// ── Handler ──────────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // ── 1. Authenticate ──────────────────────────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  let uid: string;
  try {
    const claims = await verifyFirebaseToken(
      authHeader.slice(7).trim(),
      FIREBASE_PROJECT_ID,
    );
    uid = claims.uid;
  } catch {
    return json({ error: "Invalid or expired token" }, 401);
  }

  // ── 2. Resolve user ──────────────────────────────────────────────────────
  const { data: user, error: userErr } = await supabase
    .from("users")
    .select("id, phone, household_id")
    .eq("firebase_uid", uid)
    .is("deleted_at", null)
    .maybeSingle();

  if (userErr) {
    console.error("user lookup:", userErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (!user) return json({ error: "User not found" }, 404);

  // A user may only belong to one household
  if (user.household_id) {
    return json({ error: "User already belongs to a household" }, 409);
  }

  // ── 3. Parse and validate invite code ────────────────────────────────────
  let body: { invite_code?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (typeof body.invite_code !== "string" || !body.invite_code.trim()) {
    return json({ error: "invite_code is required" }, 400);
  }

  // Normalise: uppercase and strip whitespace only — do not transform chars
  const code = body.invite_code.trim().toUpperCase();
  if (!/^[A-Z0-9]{8}$/.test(code)) {
    return json({ error: "Invite code must be 8 alphanumeric characters" }, 400);
  }

  // ── 4. Fetch invite — do NOT filter status/expiry here (return specific errors) ──
  const { data: invite, error: inviteErr } = await supabase
    .from("household_invites")
    .select("id, household_id, phone, status, expires_at")
    .eq("code", code)
    .maybeSingle();

  if (inviteErr) {
    console.error("invite lookup:", inviteErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (!invite) {
    return json({ error: "Invite code not found" }, 404);
  }

  // Specific status errors — tell the caller exactly what is wrong
  if (invite.status === "accepted") {
    return json({ error: "Invite code has already been used" }, 404);
  }
  if (invite.status === "revoked") {
    return json({ error: "Invite code has been revoked" }, 404);
  }
  if (invite.status === "expired") {
    return json({ error: "Invite code has expired" }, 404);
  }
  // Safety net: clock-based expiry (status may not have been swept yet)
  if (new Date(invite.expires_at) <= new Date()) {
    return json({ error: "Invite code has expired" }, 404);
  }

  // ── 5. Phone number must match the invite (security gate) ────────────────
  // Prevents invite codes being used by people they were not issued for.
  if (user.phone !== invite.phone) {
    return json({
      error: "This invite code was not issued for your phone number",
    }, 403);
  }

  // ── 6. Resolve and validate household ────────────────────────────────────
  const { data: household, error: hhErr } = await supabase
    .from("households")
    .select(HOUSEHOLD_COLS)
    .eq("id", invite.household_id)
    .is("deleted_at", null)
    .maybeSingle();

  if (hhErr) {
    console.error("household lookup:", hhErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (!household)          return json({ error: "Household not found" }, 404);
  if (household.suspended) return json({ error: "Household is suspended" }, 403);

  // ── 7. Re-check capacity (race condition protection) ─────────────────────
  const { count: memberCount, error: countErr } = await supabase
    .from("users")
    .select("id", { count: "exact", head: true })
    .eq("household_id", invite.household_id)
    .is("deleted_at", null);

  if (countErr) {
    console.error("capacity check:", countErr);
    return json({ error: "Internal server error" }, 500);
  }
  if ((memberCount ?? 0) >= MAX_HOUSEHOLD_SIZE) {
    return json({
      error: `Household has reached the maximum of ${MAX_HOUSEHOLD_SIZE} members`,
    }, 422);
  }

  // ── 8. Atomically claim the invite ──────────────────────────────────────
  // UPDATE returns null if status or expiry guard conditions fail —
  // meaning another concurrent request already claimed it.
  const now = new Date().toISOString();

  const { data: claimedInvite, error: claimErr } = await supabase
    .from("household_invites")
    .update({ status: "accepted" })
    .eq("id", invite.id)
    .eq("status", "pending")   // guard: reject if already claimed
    .gt("expires_at", now)     // guard: reject if expired between lookup and now
    .select("id")
    .maybeSingle();

  if (claimErr) {
    console.error("invite claim:", claimErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (!claimedInvite) {
    return json({ error: "Invite code is no longer available" }, 409);
  }

  // ── 9. Attach user to household ──────────────────────────────────────────
  // Guard: only update if the user still has no household (concurrent join protection).
  const { data: updatedUser, error: updateErr } = await supabase
    .from("users")
    .update({ household_id: invite.household_id, role: "member" })
    .eq("id", user.id)
    .is("household_id", null)  // guard: reject if already attached
    .select(USER_COLS)
    .maybeSingle();

  if (updateErr || !updatedUser) {
    // Best-effort rollback: revert invite so the admin can re-issue if needed
    await supabase
      .from("household_invites")
      .update({ status: "pending" })
      .eq("id", invite.id);

    if (updateErr) {
      console.error("user update:", updateErr);
      return json({ error: "Internal server error" }, 500);
    }
    // No error but no row updated → user gained a household concurrently
    return json({ error: "User already belongs to a household" }, 409);
  }

  return json({ user: updatedUser, household }, 201);
});
