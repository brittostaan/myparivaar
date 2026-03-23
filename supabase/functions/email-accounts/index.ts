import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface EmailAccountsRequestBody {
  action?: 'list' | 'delete'
  account_id?: string
}

/**
 * List all connected email accounts for the authenticated user's household.
 * GET /functions/v1/email-accounts
 */
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    if (req.method !== 'GET' && req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

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

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: "app" },
    })
    const supabasePublic = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: 'public' },
    })

    let action: 'list' | 'delete' = 'list'
    let accountId: string | null = null

    if (req.method === 'POST') {
      const body: EmailAccountsRequestBody = await req.json().catch(() => ({}))
      action = body.action === 'delete' ? 'delete' : 'list'
      accountId = typeof body.account_id === 'string' ? body.account_id.trim() : null
    }

    // Resolve user and household context
    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('id, household_id')
      .eq('firebase_uid', decodedToken.uid)
      .single()

    if (userError || !userData?.household_id) {
      // Keep listing resilient for users who are authenticated but not yet
      // fully provisioned in app.users/app.households.
      if (action === 'list') {
        return new Response(JSON.stringify([]), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      return new Response(JSON.stringify({ error: 'User not found or has no household' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (action === 'delete') {
      if (!accountId) {
        return new Response(JSON.stringify({ error: 'account_id is required for delete action' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const { error: deleteError } = await supabasePublic
        .from('email_accounts')
        .delete()
        .eq('id', accountId)
        .eq('household_id', userData.household_id)

      if (deleteError) {
        console.error('email-accounts delete error:', deleteError)
        return new Response(JSON.stringify({ error: 'Failed to disconnect account', debug: deleteError.message }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      return new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // List email accounts for this household (omit tokens for security)
    const { data: accounts, error: accountsError } = await supabasePublic
      .from('email_accounts')
      .select('id, email_address, provider, is_active, last_synced_at, created_at, screening_sender_filters, screening_keyword_filters, screening_scope_unit, screening_scope_value')
      .eq('household_id', userData.household_id)
      .order('created_at', { ascending: false })

    if (accountsError) {
      console.error('email-accounts DB error:', accountsError)
      return new Response(JSON.stringify({ error: 'Failed to fetch email accounts', debug: accountsError.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify(accounts ?? []), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    console.error('email-accounts error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error', debug: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
