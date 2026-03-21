import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'
import { routeAIRequest, type ChatMessage } from '../_shared/ai-router.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

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

    const {
      monthly_income,
      monthly_savings,
      monthly_expenses,
      scenario_months,
      expense_change_pct,
      income_change_pct,
    } = await req.json()

    if (!monthly_income || !monthly_expenses || !scenario_months) {
      return new Response(JSON.stringify({
        error: 'monthly_income, monthly_expenses, and scenario_months are required',
      }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

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

    const { data: household } = await supabase
      .from('households')
      .select('id, name, suspended')
      .eq('id', userData.household_id)
      .single()

    if (!household || household.suspended) {
      return new Response(JSON.stringify({ error: 'Household suspended or inactive' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Rate limit: 5/month
    const currentMonth = new Date().toISOString().substring(0, 7)
    const { data: usage } = await supabase
      .from('ai_usage')
      .select('simulator_count')
      .eq('household_id', userData.household_id)
      .eq('month', currentMonth)
      .maybeSingle()

    const used = usage?.simulator_count || 0
    const limit = 5

    if (used >= limit) {
      return new Response(JSON.stringify({
        error: 'Monthly simulation limit reached',
        limit,
        used,
      }), {
        status: 429,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get recent actual spending for baseline comparison
    const threeMonthsAgo = new Date()
    threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3)

    const { data: recentTxns } = await supabase
      .from('transactions')
      .select('amount, category, date')
      .eq('household_id', userData.household_id)
      .gte('date', threeMonthsAgo.toISOString().split('T')[0])
      .is('deleted_at', null)

    const actualMonthlySpend = (recentTxns ?? []).reduce((s: number, t: any) => s + t.amount, 0) / 3

    const { data: savingsGoals } = await supabase
      .from('savings_goals')
      .select('name, target_amount, current_amount')
      .eq('household_id', userData.household_id)
      .eq('is_active', true)

    const months = Math.min(Math.max(scenario_months || 6, 1), 24)
    const incomeChange = income_change_pct || 0
    const expenseChange = expense_change_pct || 0
    const savings = monthly_savings || 0

    const scenarioDesc = `
Family: ${household.name}
Scenario: ${months}-month projection

Inputs:
- Monthly income: ₹${monthly_income}
- Monthly expenses: ₹${monthly_expenses}
- Monthly savings target: ₹${savings}
- Income change: ${incomeChange > 0 ? '+' : ''}${incomeChange}% per month
- Expense change: ${expenseChange > 0 ? '+' : ''}${expenseChange}% per month

Baseline (actual averages, last 3 months):
- Average monthly spending: ₹${actualMonthlySpend.toFixed(0)}

${(savingsGoals ?? []).length > 0 ? `Active savings goals:\n${(savingsGoals ?? []).map((g: any) => `- ${g.name}: ₹${g.current_amount} / ₹${g.target_amount}`).join('\n')}` : 'No active savings goals.'}
`

    const messages: ChatMessage[] = [
      {
        role: 'system',
        content: `You are a financial projection tool for an Indian family finance app. Given income, expenses, savings, and change rates, project the family's finances month by month.

Return your response in this EXACT format:
PROJECTION: <3-4 sentence narrative analysis of the scenario>
BREAKDOWN: <JSON array of monthly projections>

Each entry in the BREAKDOWN array:
{
  "month": <1-based month number>,
  "income": <projected income for that month>,
  "expenses": <projected expenses>,
  "savings": <income - expenses>,
  "cumulative_savings": <running total of savings>
}

Rules:
- Apply percentage changes compound monthly
- Use Indian Rupees (₹)
- In the PROJECTION narrative, highlight key milestones (e.g., "By month 6, you'd save ₹X")
- Note risks if expenses are growing faster than income
- Do NOT give investment advice
- Be encouraging but realistic
- Round all numbers to nearest integer`,
      },
      {
        role: 'user',
        content: `Generate a ${months}-month financial projection:\n\n${scenarioDesc}`,
      },
    ]

    const result = await routeAIRequest(supabase, 'financial_simulator', messages, {
      max_tokens: 800,
      temperature: 0.4,
    })

    let projection = result.content
    let breakdown: any[] = []

    const projMatch = result.content.match(/PROJECTION:\s*([\s\S]*?)(?=BREAKDOWN:|$)/i)
    const breakdownMatch = result.content.match(/BREAKDOWN:\s*(\[[\s\S]*\])/i)

    if (projMatch) projection = projMatch[1].trim()
    if (breakdownMatch) {
      try {
        breakdown = JSON.parse(breakdownMatch[1])
      } catch {
        // Generate a simple breakdown if AI format failed
        breakdown = []
        let cumSavings = 0
        for (let i = 1; i <= months; i++) {
          const inc = monthly_income * Math.pow(1 + incomeChange / 100, i - 1)
          const exp = monthly_expenses * Math.pow(1 + expenseChange / 100, i - 1)
          const sav = inc - exp
          cumSavings += sav
          breakdown.push({
            month: i,
            income: Math.round(inc),
            expenses: Math.round(exp),
            savings: Math.round(sav),
            cumulative_savings: Math.round(cumSavings),
          })
        }
      }
    }

    // Update usage
    await supabase.from('ai_usage').upsert({
      household_id: userData.household_id,
      month: currentMonth,
      simulator_count: used + 1,
    }, { onConflict: 'household_id,month' })

    return new Response(JSON.stringify({
      projection,
      monthly_breakdown: breakdown,
      actual_monthly_avg: Math.round(actualMonthlySpend),
      uses_remaining: limit - used - 1,
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('ai-financial-simulator error:', error)
    const msg = error instanceof Error ? error.message : 'Internal server error'
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
