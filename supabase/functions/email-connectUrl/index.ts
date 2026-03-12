import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

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
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Get user's household
    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('household_id, is_active')
      .eq('firebase_uid', decodedToken.uid)
      .eq('is_active', true)
      .single()

    if (userError || !userData?.household_id) {
      return new Response(JSON.stringify({ error: 'User not found or not active' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Check household status
    const { data: household, error: householdError } = await supabase
      .from('households')
      .select('is_active, suspended_at')
      .eq('id', userData.household_id)
      .single()

    if (householdError || !household?.is_active || household.suspended_at) {
      return new Response(JSON.stringify({ error: 'Household suspended or inactive' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Generate OAuth URLs
    const defaultRedirectUri = redirect_uri || `${supabaseUrl}/functions/v1/email-oauthCallback`
    let authUrl: string
    let scopes: string[]

    if (provider === 'gmail') {
      const clientId = Deno.env.get('GOOGLE_CLIENT_ID')
      if (!clientId) {
        return new Response(JSON.stringify({ error: 'Gmail OAuth not configured' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

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
      const clientId = Deno.env.get('MICROSOFT_CLIENT_ID')
      if (!clientId) {
        return new Response(JSON.stringify({ error: 'Outlook OAuth not configured' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

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
    console.error('email-connectUrl error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})