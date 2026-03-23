import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { getOAuthCredentials } from '../_shared/oauth.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface OAuthState {
  provider: 'gmail' | 'outlook'
  household_id: string
  firebase_uid: string
}

/**
 * Handles OAuth callback from Gmail/Outlook and stores access tokens
 */
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    if (req.method !== 'GET') {
      return new Response('Method not allowed', { status: 405 })
    }

    const url = new URL(req.url)
    const code = url.searchParams.get('code')
    const state = url.searchParams.get('state')
    const error = url.searchParams.get('error')

    // Handle OAuth errors
    if (error) {
      return new Response(
        `<!DOCTYPE html><html><body><h1>Email Connection Failed</h1><p>Error: ${error}</p><p>Please close this window and try again.</p></body></html>`,
        { headers: { 'Content-Type': 'text/html' }, status: 400 }
      )
    }

    if (!code || !state) {
      return new Response(
        `<!DOCTYPE html><html><body><h1>Email Connection Failed</h1><p>Missing authorization code or state.</p></body></html>`,
        { headers: { 'Content-Type': 'text/html' }, status: 400 }
      )
    }

    // Parse state
    let oauthState: OAuthState
    try {
      oauthState = JSON.parse(state)
    } catch {
      return new Response(
        `<!DOCTYPE html><html><body><h1>Email Connection Failed</h1><p>Invalid state parameter.</p></body></html>`,
        { headers: { 'Content-Type': 'text/html' }, status: 400 }
      )
    }

    // Initialize Supabase client
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: "app" },
    })
    const supabasePublic = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: 'public' },
    })

    // Validate state user and resolve app user id for public.email_accounts.user_id
    const { data: appUser, error: appUserError } = await supabase
      .from('users')
      .select('id, household_id, is_active')
      .eq('firebase_uid', oauthState.firebase_uid)
      .eq('is_active', true)
      .single()

    if (appUserError || !appUser) {
      throw new Error('Invalid OAuth state user')
    }

    if (appUser.household_id !== oauthState.household_id) {
      throw new Error('OAuth state household mismatch')
    }

    // Exchange authorization code for tokens
    let tokenResponse: any
    let userInfo: any

    if (oauthState.provider === 'gmail') {
      const creds = await getOAuthCredentials('google')
      const redirectUri = `${supabaseUrl}/functions/v1/email-oauthCallback`

      if (!creds) {
        throw new Error('Gmail OAuth credentials not configured')
      }

      // Exchange code for tokens
      console.log('[oauthCallback] Gmail: exchanging code for tokens, redirectUri:', creds.redirectUri || redirectUri)
      const tokenReq = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          client_id: creds.clientId,
          client_secret: creds.clientSecret,
          code,
          grant_type: 'authorization_code',
          redirect_uri: creds.redirectUri || redirectUri,
        }),
      })

      tokenResponse = await tokenReq.json()
      console.log('[oauthCallback] Gmail token response status:', tokenReq.status, 'has access_token:', !!tokenResponse.access_token, 'error:', tokenResponse.error, tokenResponse.error_description)
      
      if (!tokenResponse.access_token) {
        throw new Error(`Failed to get access token from Google: ${tokenResponse.error ?? 'unknown'} - ${tokenResponse.error_description ?? ''}`)
      }

      // Get user info
      const userInfoReq = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
        headers: { Authorization: `Bearer ${tokenResponse.access_token}` },
      })

      userInfo = await userInfoReq.json()
      
    } else { // outlook
      const creds = await getOAuthCredentials('microsoft')
      const redirectUri = `${supabaseUrl}/functions/v1/email-oauthCallback`

      if (!creds) {
        throw new Error('Outlook OAuth credentials not configured')
      }

      // Exchange code for tokens
      console.log('[oauthCallback] Outlook: exchanging code for tokens, redirectUri:', creds.redirectUri || redirectUri)
      const tokenReq = await fetch('https://login.microsoftonline.com/common/oauth2/v2.0/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          client_id: creds.clientId,
          client_secret: creds.clientSecret,
          code,
          grant_type: 'authorization_code',
          redirect_uri: creds.redirectUri || redirectUri,
          scope: 'https://graph.microsoft.com/Mail.Read https://graph.microsoft.com/User.Read offline_access',
        }),
      })

      tokenResponse = await tokenReq.json()
      console.log('[oauthCallback] Outlook token response status:', tokenReq.status, 'has access_token:', !!tokenResponse.access_token, 'error:', tokenResponse.error, tokenResponse.error_description)
      
      if (!tokenResponse.access_token) {
        throw new Error(`Failed to get access token from Microsoft: ${tokenResponse.error ?? 'unknown'} - ${tokenResponse.error_description ?? ''}`)
      }

      // Get user info
      const userInfoReq = await fetch('https://graph.microsoft.com/v1.0/me', {
        headers: { Authorization: `Bearer ${tokenResponse.access_token}` },
      })

      userInfo = await userInfoReq.json()
    }

    // Calculate token expiry
    const expiresAt = tokenResponse.expires_in 
      ? new Date(Date.now() + (tokenResponse.expires_in * 1000)).toISOString()
      : null

    // Store email account in database
    const { error: insertError } = await supabasePublic
      .from('email_accounts')
      .upsert({
        household_id: oauthState.household_id,
        user_id: appUser.id,
        provider: oauthState.provider,
        email_address: userInfo.email,
        access_token: tokenResponse.access_token,
        refresh_token: tokenResponse.refresh_token || null,
        token_expires_at: expiresAt,
        is_active: true,
      }, {
        onConflict: 'household_id,email_address',
        ignoreDuplicates: false
      })

    if (insertError) {
      console.error('Database insert error:', insertError)
      throw new Error('Failed to save email account')
    }

    // Return success page
    return new Response(
      `<!DOCTYPE html>
      <html>
      <head>
        <title>Email Connected Successfully</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; text-align: center; margin: 50px; }
          .success { color: #22c55e; }
          .info { color: #6b7280; margin-top: 20px; }
        </style>
      </head>
      <body>
        <div class="success">
          <h1>✓ Email Account Connected</h1>
          <p><strong>${userInfo.email}</strong> has been connected successfully!</p>
        </div>
        <div class="info">
          <p>You can now close this window and return to the myParivaar app.</p>
          <p>Your emails will be synced automatically to detect transactions.</p>
        </div>
      </body>
      </html>`,
      { 
        headers: { 'Content-Type': 'text/html' }, 
        status: 200 
      }
    )

  } catch (error) {
    const errMsg = error instanceof Error ? error.message : String(error)
    console.error('email-oauthCallback error:', errMsg, error)
    
    return new Response(
      `<!DOCTYPE html>
      <html>
      <head>
        <title>Email Connection Failed</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; text-align: center; margin: 50px; }
          .error { color: #ef4444; }
          .details { color: #6b7280; font-size: 14px; margin-top: 20px; padding: 12px; background: #f3f4f6; border-radius: 8px; text-align: left; display: inline-block; max-width: 600px; word-break: break-all; }
        </style>
      </head>
      <body>
        <div class="error">
          <h1>Email Connection Failed</h1>
          <p>There was an error connecting your email account.</p>
          <div class="details"><strong>Error:</strong> ${errMsg}</div>
          <p style="margin-top:20px">Please close this window and try again.</p>
        </div>
      </body>
      </html>`,
      { 
        headers: { 'Content-Type': 'text/html' }, 
        status: 500 
      }
    )
  }
})