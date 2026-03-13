/**
 * household-remove
 *
 * Admin-only. Soft-removes a member from the household by setting is_active = false.
 * The caller cannot remove themselves or the household admin.
 *
 * POST /functions/v1/household-remove
 * Header:  Authorization: Bearer <firebase_id_token>
 * Body:    { "member_user_id": "<uuid>" }
 *
 * Responses
 *   200  { ok: true }
 *   400  invalid input / cannot remove self / cannot remove admin
 *   401  unauthenticated
 *   403  caller inactive / not admin / no household / household suspended
 *   404  caller not found / target member not found in this household
 *   405  wrong method
 *   409  member is already inactive
 *   500  server error
 *
 * Tables used (app schema):
 *   app.users, app.households
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyFirebaseToken } from "../_shared/firebase.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  {
    auth: { persistSession: false },
    db: { schema: "app" },
  },
);

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

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
    const claims = await verifyFirebaseToken(authHeader.slice(7).trim());
    uid = claims.uid;
  } catch {
    return json({ error: "Invalid or expired token" }, 401);
  }

  // ── 2. Resolve caller ────────────────────────────────────────────────────
  const { data: caller, error: callerErr } = await supabase
    .from("users")
    .select("id, household_id, role, is_active")
    .eq("firebase_uid", uid)
    .maybeSingle();

  if (callerErr) {
    console.error("caller lookup:", callerErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (!caller) {
    return json({ error: "User not found" }, 404);
  }
  if (!caller.is_active) {
    return json({ error: "Account is inactive" }, 403);
  }
  if (!caller.household_id) {
    return json({ error: "User does not belong to a household" }, 403);
  }
  if (caller.role !== "admin" && caller.role !== "super_admin") {
    return json({ error: "Only the household admin can remove members" }, 403);
  }

  // ── 3. Resolve household (suspended check) ───────────────────────────────
  const { data: household, error: hhErr } = await supabase
    .from("households")
    .select("id, suspended")
    .eq("id", caller.household_id)
    .maybeSingle();

  if (hhErr) {
    console.error("household lookup:", hhErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (!household) {
    return json({ error: "Household not found" }, 404);
  }
  if (household.suspended) {
    return json({ error: "Household is suspended" }, 403);
  }

  // ── 4. Parse and validate body ───────────────────────────────────────────
  let body: { member_user_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (
    typeof body.member_user_id !== "string" ||
    !body.member_user_id.trim()
  ) {
    return json({ error: "member_user_id is required" }, 400);
  }

  const memberUserId = body.member_user_id.trim();

  if (!UUID_RE.test(memberUserId)) {
    return json({ error: "member_user_id must be a valid UUID" }, 400);
  }

  // ── 5. Business rule: cannot remove self ─────────────────────────────────
  if (memberUserId === caller.id) {
    return json({ error: "Admin cannot remove themselves from the household" }, 400);
  }

  // ── 6. Fetch target member — must be in the same household ───────────────
  const { data: target, error: targetErr } = await supabase
    .from("users")
    .select("id, role, household_id, is_active")
    .eq("id", memberUserId)
    .eq("household_id", caller.household_id)
    .maybeSingle();

  if (targetErr) {
    console.error("target lookup:", targetErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (!target) {
    // Either the user does not exist or belongs to a different household.
    // Do not reveal which — return a single consistent message.
    return json({ error: "Member not found in this household" }, 404);
  }

  // ── 7. Business rule: cannot remove the household admin ──────────────────
  if (target.role === "admin") {
    return json({ error: "The household admin cannot be removed" }, 400);
  }

  // ── 8. Guard: already inactive ───────────────────────────────────────────
  if (!target.is_active) {
    return json({ error: "Member is already inactive" }, 409);
  }

  // ── 9. Soft-remove: set is_active = false ────────────────────────────────
  const { error: updateErr } = await supabase
    .from("users")
    .update({ is_active: false })
    .eq("id", target.id)
    .eq("household_id", caller.household_id) // belt-and-suspenders ownership guard
    .eq("is_active", true);                  // guard: reject if already deactivated

  if (updateErr) {
    console.error("member deactivate:", updateErr);
    return json({ error: "Internal server error" }, 500);
  }

  return json({ ok: true }, 200);
});
