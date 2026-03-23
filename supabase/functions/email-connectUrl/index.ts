import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'
import { getOAuthCredentials } from '../_shared/oauth.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface EmailConnectRequest {
  provider: 'gmail' | 'outlook'
  redirect_uri?: string
}

/**
 * Initiates OAuth flow for Gmail/Outlook email account connection
 */
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Verify Firebase authentication
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ error: 'Missing authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const idToken = authHeader.split('Bearer ')[1]
    const decodedToken = await verifyFirebaseToken(idToken)
    
    if (!decodedToken?.uid) {
      return new Response(JSON.stringify({ error: 'Invalid auth token' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Parse request body
    const { provider, redirect_uri }: EmailConnectRequest = await req.json()
    
    if (!provider || !['gmail', 'outlook'].includes(provider)) {
      return new Response(JSON.stringify({ error: 'Invalid provider. Must be gmail or outlook' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Initialize Supabase client
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: "app" },
    })

    // Get user's household. Primary lookup by firebase_uid, fallback by email
    // for legacy users created before firebase_uid mapping stabilization.
    let { data: userData, error: userError } = await supabase
      .from('users')
      .select('id, household_id, is_active, firebase_uid, email')
      .eq('firebase_uid', decodedToken.uid)
      .eq('is_active', true)
      .maybeSingle()

    if ((!userData || !userData.household_id) && decodedToken.email) {
      const fallback = await supabase
        .from('users')
        .select('id, household_id, is_active, firebase_uid, email')
        .eq('email', decodedToken.email)
        .eq('is_active', true)
        .maybeSingle()

      if (!fallback.error && fallback.data?.household_id) {
        userData = fallback.data
        userError = null

        // Self-heal firebase_uid mapping for future requests.
        if (userData.firebase_uid !== decodedToken.uid) {
          await supabase
            .from('users')
            .update({ firebase_uid: decodedToken.uid })
            .eq('id', userData.id)
        }
      }
    }

    if (userError || !userData?.household_id) {
      return new Response(JSON.stringify({
        error: 'User profile not linked to an active household. Please sign out/in and retry.',
      }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Check household status
    const { data: household, error: householdError } = await supabase
      .from('households')
      .select('suspended, deleted_at')
      .eq('id', userData.household_id)
      .single()

    if (householdError || household?.suspended || household?.deleted_at) {
      return new Response(JSON.stringify({ error: 'Household suspended or inactive' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Generate OAuth URLs
    let authUrl: string
    let scopes: string[]

    if (provider === 'gmail') {
      const creds = await getOAuthCredentials('google')
      if (!creds) {
        return new Response(JSON.stringify({ error: 'Gmail OAuth not configured. Admin must set up Google credentials in Admin Center → Email Admin.' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      const clientId = creds.clientId
      const defaultRedirectUri = creds.redirectUri || redirect_uri || `${supabaseUrl}/functions/v1/email-oauthCallback`

      scopes = [
        'https://www.googleapis.com/auth/gmail.readonly',
        'https://www.googleapis.com/auth/userinfo.email'
      ]
      
      const params = new URLSearchParams({
        client_id: clientId,
        redirect_uri: defaultRedirectUri,
        response_type: 'code',
        scope: scopes.join(' '),
        access_type: 'offline',
        prompt: 'consent',
        state: JSON.stringify({
          provider: 'gmail',
          household_id: userData.household_id,
          firebase_uid: decodedToken.uid
        })
      })

      authUrl = `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`
      
    } else { // outlook
      const creds = await getOAuthCredentials('microsoft')
      if (!creds) {
        return new Response(JSON.stringify({ error: 'Outlook OAuth not configured. Admin must set up Microsoft credentials in Admin Center → Email Admin.' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      const clientId = creds.clientId
      const defaultRedirectUri = creds.redirectUri || redirect_uri || `${supabaseUrl}/functions/v1/email-oauthCallback`

      scopes = [
        'https://graph.microsoft.com/Mail.Read',
        'https://graph.microsoft.com/User.Read',
        'offline_access'
      ]

      const params = new URLSearchParams({
        client_id: clientId,
        redirect_uri: defaultRedirectUri,
        response_type: 'code',
        scope: scopes.join(' '),
        response_mode: 'query',
        state: JSON.stringify({
          provider: 'outlook',
          household_id: userData.household_id,
          firebase_uid: decodedToken.uid
        })
      })

      authUrl = `https://login.microsoftonline.com/common/oauth2/v2.0/authorize?${params.toString()}`
    }

    return new Response(
      JSON.stringify({
        auth_url: authUrl,
        provider,
        scopes,
        expires_in: 300 // OAuth flow should complete within 5 minutes
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )

  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    console.error('email-connectUrl error:', {
      message: errorMsg,
      stack: error instanceof Error ? error.stack : undefined,
      errorType: typeof error,
    });
    
    // Return real error message to help client diagnose
    return new Response(
      JSON.stringify({ 
        error: errorMsg || 'Internal server error',
        details: 'See function logs for more information'
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})