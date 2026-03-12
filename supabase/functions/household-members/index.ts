/**
 * household-members
 *
 * Returns all active members of the caller's household.
 * Sorted: admin first, then remaining members by created_at ascending.
 *
 * POST /functions/v1/household-members
 * Header:  Authorization: Bearer <firebase_id_token>
 * Body:    {} (empty, ignored)
 *
 * Response shape (200):
 *   { members: Array<{ id, name, phone_number, role, is_active, created_at }> }
 *
 * DB column mapping (app.users):
 *   display_name → name          (response key expected by Flutter)
 *   phone        → phone_number  (response key expected by Flutter)
 *   firebase_uid is intentionally never returned.
 *
 * Error responses:
 *   401  missing / invalid / expired Firebase token
 *   403  caller inactive | no household | household suspended
 *   404  caller not found | household not found
 *   405  wrong HTTP method
 *   500  unexpected server error
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyFirebaseToken } from "../_shared/firebase.ts";

// ── Constants ────────────────────────────────────────────────────────────────

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

// ── Supabase service-role client (bypasses RLS, targets app schema) ──────────

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  {
    auth: { persistSession: false },
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

// ── Member shape returned to the client ──────────────────────────────────────

interface MemberResponse {
  id: string;
  name: string | null;       // mapped from display_name
  phone_number: string;      // mapped from phone
  role: string;
  is_active: boolean;
  created_at: string;
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
    const claims = await verifyFirebaseToken(
      authHeader.slice(7).trim(),
      FIREBASE_PROJECT_ID,
    );
    uid = claims.uid;
  } catch {
    return json({ error: "Invalid or expired token" }, 401);
  }

  // ── 2. Resolve caller ────────────────────────────────────────────────────
  // Select only what we need to authorise the request.
  // firebase_uid is not returned to the client at any point.
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

  // ── 3. Validate household (suspended check) ──────────────────────────────
  const { data: household, error: hhErr } = await supabase
    .from("households")
    .select("id")
    .eq("id", caller.household_id)
    .maybeSingle();

  if (hhErr) {
    console.error("household lookup:", hhErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (!household) {
    return json({ error: "Household not found" }, 404);
  }

  // ── 4. Fetch active household members ────────────────────────────────────
  // Selects the actual DB column names (phone, display_name) and remaps them
  // to the response keys Flutter expects (phone_number, name).
  // firebase_uid is intentionally absent from this select list.
  const { data: rows, error: membersErr } = await supabase
    .from("users")
    .select("id, display_name, name, phone, phone_number, role, is_active, created_at")
    .eq("household_id", caller.household_id)
    .eq("is_active", true)
    .order("created_at", { ascending: true });

  if (membersErr) {
    console.error("members fetch:", membersErr);
    return json({ error: "Internal server error" }, 500);
  }

  // ── 5. Remap columns + sort (admin first, then by created_at asc) ─────────
  const members: MemberResponse[] = (rows ?? [])
    .map((row) => ({
      id:           row.id           as string,
      name:         ((row.display_name ?? row.name) ?? null) as string | null,
      phone_number: ((row.phone_number ?? row.phone) ?? "") as string,
      role:         row.role         as string,
      is_active:    row.is_active    as boolean,
      created_at:   row.created_at   as string,
    }))
    .sort((a, b) => {
      if (a.role === "admin" && b.role !== "admin") return -1;
      if (a.role !== "admin" && b.role === "admin") return 1;
      return 0; // DB already returned rows in created_at asc order
    });

  return json({ members }, 200);
});
