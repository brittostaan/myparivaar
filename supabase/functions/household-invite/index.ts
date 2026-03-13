/**
 * household-invite
 *
 * Admin-only. Generates a time-limited invite code for a phone number
 * to join the household. No SMS is sent — admin shares the code out-of-band.
 *
 * POST /functions/v1/household-invite
 * Header:  Authorization: Bearer <firebase_id_token>
 * Body:    { "phone_number": "+919876543210" }
 *
 * Responses
 *   201  { invite_code, phone_number, expires_at }
 *   400  invalid input
 *   401  unauthenticated
 *   403  not admin / no household / household suspended
 *   404  user not found
 *   405  wrong method
 *   409  phone already a member, or pending invite already exists
 *   422  household at capacity (max 8)
 *   500  server error
 *
 * Tables used (app schema):
 *   app.users, app.households, app.household_invites
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyFirebaseToken } from "../_shared/firebase.ts";

// ── Constants ────────────────────────────────────────────────────────────────
const MAX_HOUSEHOLD_SIZE  = 8;
const INVITE_EXPIRY_DAYS  = 7;

// Omit visually ambiguous chars: 0, 1, I, O
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 32 chars → uniform with byte % 32
const CODE_LENGTH   = 8;

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

// ── Helpers ──────────────────────────────────────────────────────────────────
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/**
 * Generates a cryptographically random, human-readable invite code.
 * 32-char alphabet divides 256 evenly → uniform distribution, no bias.
 */
function generateInviteCode(): string {
  const bytes = new Uint8Array(CODE_LENGTH);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
}

/**
 * Normalises a phone number to E.164.
 * Accepts: +91XXXXXXXXXX | 91XXXXXXXXXX | 0XXXXXXXXXX | XXXXXXXXXX (India default)
 * Returns null for unrecognised formats.
 */
function normalizePhone(raw: string): string | null {
  const s = raw.trim().replace(/[\s\-().]/g, "");

  // Already valid E.164 (+<country><number>, 8–15 digits)
  if (/^\+\d{8,15}$/.test(s)) return s;

  // +91 already stripped but digits remain → 91XXXXXXXXXX
  if (/^91\d{10}$/.test(s)) return `+${s}`;

  // Leading 0 → Indian landline/mobile → 0XXXXXXXXXX
  if (/^0\d{10}$/.test(s)) return `+91${s.slice(1)}`;

  // Bare 10-digit Indian mobile
  if (/^\d{10}$/.test(s)) return `+91${s}`;

  return null;
}

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
    const claims = await verifyFirebaseToken(authHeader.slice(7).trim());
    uid = claims.uid;
  } catch {
    return json({ error: "Invalid or expired token" }, 401);
  }

  // ── 2. Resolve caller — must be admin with a household ───────────────────
  const { data: caller, error: callerErr } = await supabase
    .from("users")
    .select("id, role, household_id")
    .eq("firebase_uid", uid)
    .is("deleted_at", null)
    .maybeSingle();

  if (callerErr) {
    console.error("caller lookup:", callerErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (!caller)              return json({ error: "User not found" }, 404);
  if (!caller.household_id) return json({ error: "User does not belong to a household" }, 403);
  if (caller.role !== "admin" && caller.role !== "super_admin") {
    return json({ error: "Only the household admin can invite members" }, 403);
  }

  // ── 3. Resolve household ─────────────────────────────────────────────────
  const { data: household, error: hhErr } = await supabase
    .from("households")
    .select("id, suspended")
    .eq("id", caller.household_id)
    .is("deleted_at", null)
    .maybeSingle();

  if (hhErr) {
    console.error("household lookup:", hhErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (!household)          return json({ error: "Household not found" }, 404);
  if (household.suspended) return json({ error: "Household is suspended" }, 403);

  const householdId = household.id as string;
  const callerId    = caller.id    as string;

  // ── 4. Validate phone number ─────────────────────────────────────────────
  let body: { phone_number?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (typeof body.phone_number !== "string" || !body.phone_number.trim()) {
    return json({ error: "phone_number is required" }, 400);
  }

  const phone = normalizePhone(body.phone_number);
  if (!phone) {
    return json({
      error: "Invalid phone number. Provide E.164 format (e.g. +919876543210) or a 10-digit Indian number",
    }, 400);
  }

  // ── 5. Enforce household capacity ───────────────────────────────────────
  // Capacity = current active members + pending non-expired invites
  const now = new Date().toISOString();

  const [
    { count: memberCount,  error: memberCountErr  },
    { count: pendingCount, error: pendingCountErr },
  ] = await Promise.all([
    supabase
      .from("users")
      .select("id", { count: "exact", head: true })
      .eq("household_id", householdId)
      .is("deleted_at", null),
    supabase
      .from("household_invites")
      .select("id", { count: "exact", head: true })
      .eq("household_id", householdId)
      .eq("status", "pending")
      .gt("expires_at", now),
  ]);

  if (memberCountErr || pendingCountErr) {
    console.error("capacity check:", { memberCountErr, pendingCountErr });
    return json({ error: "Internal server error" }, 500);
  }

  if ((memberCount ?? 0) + (pendingCount ?? 0) >= MAX_HOUSEHOLD_SIZE) {
    return json({
      error: `Household has reached the maximum of ${MAX_HOUSEHOLD_SIZE} members`,
    }, 422);
  }

  // ── 6. Phone must not already be an active member ────────────────────────
  const { data: activeMember, error: activeMemberErr } = await supabase
    .from("users")
    .select("id")
    .eq("phone", phone)
    .eq("household_id", householdId)
    .is("deleted_at", null)
    .maybeSingle();

  if (activeMemberErr) {
    console.error("member check:", activeMemberErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (activeMember) {
    return json({ error: "This phone number is already a member of the household" }, 409);
  }

  // ── 7. No duplicate pending invite for same phone ────────────────────────
  const { data: dupInvite, error: dupErr } = await supabase
    .from("household_invites")
    .select("id, expires_at")
    .eq("household_id", householdId)
    .eq("phone", phone)
    .eq("status", "pending")
    .gt("expires_at", now)
    .maybeSingle();

  if (dupErr) {
    console.error("duplicate invite check:", dupErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (dupInvite) {
    return json({
      error: "A pending invite already exists for this phone number",
      expires_at: dupInvite.expires_at,
    }, 409);
  }

  // ── 8. Create invite (retry on code collision, max 3 attempts) ───────────
  const expiresAt = new Date(
    Date.now() + INVITE_EXPIRY_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();

  type InviteRow = { id: string; code: string; expires_at: string };
  let created: InviteRow | null = null;

  for (let attempt = 0; attempt < 3; attempt++) {
    const { data, error: insertErr } = await supabase
      .from("household_invites")
      .insert({
        household_id:       householdId,
        invited_by_user_id: callerId,
        phone,
        code:               generateInviteCode(),
        status:             "pending",
        expires_at:         expiresAt,
      })
      .select("id, code, expires_at")
      .single();

    if (!insertErr) {
      created = data as InviteRow;
      break;
    }

    // 23505 = unique_violation on code column — retry with a new code
    if (insertErr.code !== "23505") {
      console.error("invite insert:", insertErr);
      return json({ error: "Internal server error" }, 500);
    }
  }

  if (!created) {
    console.error("Failed to generate a unique invite code after 3 attempts");
    return json({ error: "Internal server error" }, 500);
  }

  return json({
    invite_code:  created.code,
    phone_number: phone,
    expires_at:   created.expires_at,
  }, 201);
});
