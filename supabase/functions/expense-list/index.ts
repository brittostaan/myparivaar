import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface ExpenseListRequest {
  limit?: number
  category?: string
  start_date?: string
  end_date?: string
}

/**
 * List expenses for the authenticated user's household
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

    // Verify Supabase authentication
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
    const { limit = 500, category, start_date, end_date }: ExpenseListRequest = await req.json().catch(() => ({}))

    // Initialize Supabase client
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: "app" },
    })

    // Get user's household
    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('household_id')
      .eq('firebase_uid', decodedToken.uid)
      .single()

    if (userError || !userData?.household_id) {
      return new Response(JSON.stringify({
        error: 'User not found or not active',
        debug: { uid: decodedToken.uid, dbError: userError?.message, userData }
      }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Ensure household exists
    const { data: household, error: householdError } = await supabase
      .from('households')
      .select('id')
      .eq('id', userData.household_id)
      .single()

    if (householdError || !household?.id) {
      return new Response(JSON.stringify({
        error: 'Household not found',
        debug: { household_id: userData.household_id, dbError: householdError?.message }
      }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Build query
    let query = supabase
      .from('transactions')
      .select('*')
      .eq('household_id', userData.household_id)
      .is('deleted_at', null)
      .order('date', { ascending: false })
      .limit(Math.min(limit, 5000)) // Max 5000 records

    if (category) {
      query = query.eq('category', category.toLowerCase())
    }

    if (start_date) {
      query = query.gte('date', start_date)
    }

    if (end_date) {
      query = query.lte('date', end_date)
    }

    const { data: expenses, error: expensesError } = await query

    if (expensesError) {
      console.error('Database error:', expensesError)
      return new Response(JSON.stringify({ 
        error: 'Failed to fetch expenses',
        debug: {
          message: expensesError.message,
          code: expensesError.code,
          details: expensesError.details,
          hint: expensesError.hint,
        }
      }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(
      JSON.stringify({ 
        expenses: expenses || [],
        count: expenses?.length || 0
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )

  } catch (error) {
    console.error('expense-list error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', debug: { exception: String(error) } }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})