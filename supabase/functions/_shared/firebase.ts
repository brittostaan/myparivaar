/**
 * Token verification helper used across Edge Functions.
 *
 * NOTE: Kept function name for backward compatibility with existing imports,
 * but this now verifies Supabase Auth JWTs via supabase.auth.getUser().
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

export interface FirebaseClaims {
  uid: string;
  phone_number: string | undefined;
  email: string | undefined;
}

/**
 * Verifies a Supabase Auth JWT by calling supabase.auth.getUser().
 * This works without needing the JWT secret as an env var.
 * Throws on invalid/expired tokens.
 */
export async function verifyFirebaseToken(
  idToken: string,
  _projectId?: string,
): Promise<FirebaseClaims> {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: { user }, error } = await supabase.auth.getUser(idToken);

  if (error || !user) {
    const errorMsg = error?.message ?? "Invalid or expired token";
    const errorCode = (error as any)?.code ?? "UNKNOWN_ERROR";
    console.error("[firebase.ts] Token verification failed", {
      errorCode,
      errorMsg,
      hasUser: !!user,
      supabaseUrl: SUPABASE_URL,
      tokenLength: idToken.length,
    });
    throw new Error(errorMsg);
  }

  console.log("[firebase.ts] Token verified successfully for user", { uid: user.id });

  return {
    uid: user.id,
    phone_number: user.phone ?? undefined,
    email: user.email ?? undefined,
  };
}
