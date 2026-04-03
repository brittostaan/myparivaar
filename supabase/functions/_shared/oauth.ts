/**
 * Shared helper for reading OAuth provider credentials.
 *
 * Reads from app.oauth_provider_configs table first (admin-configured via UI).
 * Falls back to environment variables for backward compatibility.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

export interface OAuthCredentials {
  clientId: string
  clientSecret: string
  redirectUri: string | null
  source: 'database' | 'env'
}

/**
 * Returns OAuth credentials for the given provider ('google' | 'microsoft').
 * Checks the database first, then falls back to environment variables.
 * Returns null if neither source has credentials configured.
 */
export async function getOAuthCredentials(
  provider: 'google' | 'microsoft',
): Promise<OAuthCredentials | null> {
  // 1. Try database first
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      db: { schema: 'app' },
    })

    const { data, error } = await supabase
      .from('oauth_provider_configs')
      .select('client_id, client_secret, redirect_uri, is_active')
      .eq('provider', provider)
      .eq('is_active', true)
      .maybeSingle()

    if (!error && data?.client_id && data?.client_secret) {
      console.log(`[oauth] Using DB credentials for ${provider}`)
      return {
        clientId: data.client_id,
        clientSecret: data.client_secret,
        redirectUri: data.redirect_uri ?? null,
        source: 'database',
      }
    }
  } catch (err) {
    console.warn(`[oauth] DB lookup failed for ${provider}, falling back to env:`, err)
  }

  // 2. Fallback to environment variables
  if (provider === 'google') {
    const clientId = Deno.env.get('GOOGLE_CLIENT_ID')
    const clientSecret = Deno.env.get('GOOGLE_CLIENT_SECRET')
    if (clientId && clientSecret) {
      console.log(`[oauth] Using env credentials for ${provider}`)
      return { clientId, clientSecret, redirectUri: null, source: 'env' }
    }
  } else {
    const clientId = Deno.env.get('MICROSOFT_CLIENT_ID')
    const clientSecret = Deno.env.get('MICROSOFT_CLIENT_SECRET')
    if (clientId && clientSecret) {
      console.log(`[oauth] Using env credentials for ${provider}`)
      return { clientId, clientSecret, redirectUri: null, source: 'env' }
    }
  }

  return null
}
