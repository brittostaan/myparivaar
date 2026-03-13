import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const MONTH_RE = /^\d{4}-(0[1-9]|1[0-2])$/

function toMonth(date: Date): string {
  const y = date.getUTCFullYear()
  const m = String(date.getUTCMonth() + 1).padStart(2, '0')
  return `${y}-${m}`
}

function monthRange(month: string): { start: string; end: string } {
  const [y, m] = month.split('-').map(Number)
  const start = new Date(Date.UTC(y, m - 1, 1))
  const end = new Date(Date.UTC(y, m, 1))
  return {
    start: start.toISOString().split('T')[0],
    end: end.toISOString().split('T')[0],
  }
}

function previousMonth(month: string): string {
  const [y, m] = month.split('-').map(Number)
  const d = new Date(Date.UTC(y, m - 2, 1))
  return toMonth(d)
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders })

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  try {
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

    const body = await req.json().catch(() => ({})) as { month?: string }
    const currentMonth = body.month && MONTH_RE.test(body.month) ? body.month : toMonth(new Date())
    const prevMonth = previousMonth(currentMonth)

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: 'app' },
    })

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

    const curRange = monthRange(currentMonth)
    const prevRange = monthRange(prevMonth)

    const { data: curTx, error: curErr } = await supabase
      .from('transactions')
      .select('amount, category')
      .eq('household_id', userData.household_id)
      .is('deleted_at', null)
      .gte('date', curRange.start)
      .lt('date', curRange.end)

    if (curErr) {
      return new Response(JSON.stringify({ error: 'Failed to load current month stats' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: prevTx, error: prevErr } = await supabase
      .from('transactions')
      .select('amount, category')
      .eq('household_id', userData.household_id)
      .is('deleted_at', null)
      .gte('date', prevRange.start)
      .lt('date', prevRange.end)

    if (prevErr) {
      return new Response(JSON.stringify({ error: 'Failed to load previous month stats' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const expenseCategories = new Set(['income', 'salary'])
    const currentExpenseTotal = (curTx ?? []).reduce((sum, row) => {
      const cat = String(row.category ?? '').toLowerCase()
      if (expenseCategories.has(cat)) return sum
      return sum + Number(row.amount ?? 0)
    }, 0)

    const previousExpenseTotal = (prevTx ?? []).reduce((sum, row) => {
      const cat = String(row.category ?? '').toLowerCase()
      if (expenseCategories.has(cat)) return sum
      return sum + Number(row.amount ?? 0)
    }, 0)

    const totalBalance = -currentExpenseTotal
    const percentageChange = previousExpenseTotal > 0
      ? ((currentExpenseTotal - previousExpenseTotal) / previousExpenseTotal) * 100
      : 0

    return new Response(JSON.stringify({
      month: currentMonth,
      total_balance: Number(totalBalance.toFixed(2)),
      percentage_change: Number(percentageChange.toFixed(2)),
      current_month_expenses: Number(currentExpenseTotal.toFixed(2)),
      previous_month_expenses: Number(previousExpenseTotal.toFixed(2)),
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: 'Internal server error', detail: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
