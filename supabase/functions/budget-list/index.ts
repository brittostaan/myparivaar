import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface BudgetListRequest {
  month: string // YYYY-MM
}

/**
 * List budgets for the authenticated user's household, with real spent amounts
 * computed from app.transactions for the requested month.
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

    const { month }: BudgetListRequest = await req.json().catch(() => ({}))

    if (!month || !/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) {
      return new Response(JSON.stringify({ error: 'Invalid month format. Use YYYY-MM' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: 'app' },
    })

    // Resolve household
    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('household_id')
      .eq('firebase_uid', decodedToken.uid)
      .single()

    if (userError || !userData?.household_id) {
      return new Response(JSON.stringify({ error: 'User not found or not in a household' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const householdId = userData.household_id

    // Fetch budgets for this household + month
    const { data: budgets, error: budgetsError } = await supabase
      .from('budgets')
      .select('*')
      .eq('household_id', householdId)
      .eq('month', month)
      .is('deleted_at', null)
      .order('category', { ascending: true })

    if (budgetsError) {
      console.error('budget-list DB error:', budgetsError)
      return new Response(JSON.stringify({ error: 'Failed to fetch budgets' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Compute spent amounts from transactions for each category in the month
    // Date range: first day of month to first day of next month (exclusive)
    const [year, mon] = month.split('-').map(Number)
    const startDate = `${month}-01`
    const nextMonth = mon === 12
      ? `${year + 1}-01-01`
      : `${year}-${String(mon + 1).padStart(2, '0')}-01`

    // Build a category→spent map via a single aggregate query
    const spentMap: Record<string, number> = {}

    if (budgets && budgets.length > 0) {
      const categories = budgets.map((b: { category: string }) => b.category)

      const { data: txRows, error: txError } = await supabase
        .from('transactions')
        .select('category, amount')
        .eq('household_id', householdId)
        .in('category', categories)
        .in('status', ['approved', 'pending'])
        .is('deleted_at', null)
        .gte('date', startDate)
        .lt('date', nextMonth)

      if (txError) {
        console.error('budget-list transactions error:', txError)
        // Non-fatal: return budgets with spent=0 rather than failing
      } else if (txRows) {
        for (const row of txRows) {
          spentMap[row.category] = (spentMap[row.category] ?? 0) + Number(row.amount)
        }
      }
    }

    // Attach spent to each budget row
    const result = (budgets ?? []).map((b: Record<string, unknown>) => ({
      ...b,
      spent: spentMap[b.category as string] ?? 0,
    }))

    return new Response(
      JSON.stringify({ budgets: result, count: result.length }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('budget-list error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
