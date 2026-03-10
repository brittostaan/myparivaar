/**
 * Firebase ID token verification for Deno Edge Functions.
 *
 * Uses Firebase's JWK endpoint (RS256).
 * Caches the JWKS in module scope — reused across warm invocations.
 */
import { createRemoteJWKSet, jwtVerify } from "https://deno.land/x/jose@v5.2.4/index.ts";

const FIREBASE_JWKS_URL =
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

// Module-level cache — survives across warm invocations of the same worker.
let _jwks: ReturnType<typeof createRemoteJWKSet> | null = null;

function getJwks(): ReturnType<typeof createRemoteJWKSet> {
  if (!_jwks) {
    _jwks = createRemoteJWKSet(new URL(FIREBASE_JWKS_URL));
  }
  return _jwks;
}

export interface FirebaseClaims {
  uid: string;
  phone_number: string | undefined;
}

/**
 * Verifies a Firebase Phone Auth ID token.
 * Throws on invalid/expired tokens.
 */
export async function verifyFirebaseToken(
  idToken: string,
  projectId: string,
): Promise<FirebaseClaims> {
  const { payload } = await jwtVerify(idToken, getJwks(), {
    issuer: `https://securetoken.google.com/${projectId}`,
    audience: projectId,
    algorithms: ["RS256"],
  });

  if (!payload.sub) {
    throw new Error("Token missing sub claim");
  }

  return {
    uid: payload.sub,
    phone_number: payload["phone_number"] as string | undefined,
  };
}
