/**
 * user-update
 *
 * Updates the authenticated user's profile fields.
 *
 * POST /functions/v1/user-update
 * Header:  Authorization: Bearer <supabase_jwt_token>
 * Body:    { display_name?, first_name?, last_name?, phone?, date_of_birth?, photo_url? }
 *
 * Responses
 *   200  { user }        updated user record
 *   400  invalid input
 *   401  unauthenticated
 *   404  user not found
 *   405  wrong method
 *   500  server error
 *
 * Tables used (app schema):
 *   app.users
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const USER_COLS =
  "id, firebase_uid, email, phone, role, household_id, staff_role, staff_scope, admin_permissions, display_name, first_name, last_name, date_of_birth, photo_url, notifications_enabled, voice_enabled, created_at";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // ── 1. Verify Supabase JWT ───────────────────────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Missing or malformed Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const token = authHeader.slice(7).trim();

    // Verify token via Supabase Auth
    const anonClient = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { auth: { persistSession: false } },
    );
    const { data: { user: authUser }, error: authError } = await anonClient.auth.getUser(token);
    if (authError || !authUser) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── 2. Parse body ────────────────────────────────────────────────────
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid JSON body" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── 3. Build update payload (whitelist allowed fields) ───────────────
    const update: Record<string, unknown> = {};
    const allowedStringFields = ["display_name", "first_name", "last_name", "phone", "photo_url"];

    for (const field of allowedStringFields) {
      if (body[field] !== undefined) {
        const val = body[field];
        if (val === null || val === "") {
          update[field] = null;
        } else if (typeof val === "string") {
          const trimmed = val.trim();
          if (trimmed.length > 200) {
            return new Response(
              JSON.stringify({ error: `${field} is too long (max 200 characters)` }),
              { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
            );
          }
          update[field] = trimmed;
        }
      }
    }

    // date_of_birth — validate ISO date format
    if (body.date_of_birth !== undefined) {
      if (body.date_of_birth === null || body.date_of_birth === "") {
        update.date_of_birth = null;
      } else if (typeof body.date_of_birth === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.date_of_birth)) {
        update.date_of_birth = body.date_of_birth;
      } else {
        return new Response(
          JSON.stringify({ error: "date_of_birth must be YYYY-MM-DD format" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    if (Object.keys(update).length === 0) {
      return new Response(
        JSON.stringify({ error: "No valid fields to update" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── 4. Update user in app schema ─────────────────────────────────────
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: "app" },
    });

    const { data: updatedUser, error: updateError } = await supabase
      .from("users")
      .update(update)
      .eq("firebase_uid", authUser.id)
      .select(USER_COLS)
      .single();

    if (updateError) {
      console.error("user-update DB error:", updateError);
      if (updateError.code === "PGRST116") {
        return new Response(
          JSON.stringify({ error: "User not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      return new Response(
        JSON.stringify({ error: "Failed to update profile" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(JSON.stringify({ user: updatedUser }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("user-update error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
