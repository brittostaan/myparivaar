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

    // Rate limit: 3/month
    const currentMonth = new Date().toISOString().substring(0, 7)
    const { data: usage } = await supabase
      .from('ai_usage')
      .select('budget_analysis_count')
      .eq('household_id', userData.household_id)
      .eq('month', currentMonth)
      .maybeSingle()

    const used = usage?.budget_analysis_count || 0
    const limit = 3

    if (used >= limit) {
      return new Response(JSON.stringify({
        error: 'Monthly budget analysis limit reached',
        limit,
        used,
      }), {
        status: 429,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Gather budget + spending data for current month
    const { data: budgets } = await supabase
      .from('budgets')
      .select('category, amount, month')
      .eq('household_id', userData.household_id)
      .eq('month', currentMonth)

    const monthStart = `${currentMonth}-01`
    const { data: transactions } = await supabase
      .from('transactions')
      .select('amount, category, description, date')
      .eq('household_id', userData.household_id)
      .gte('date', monthStart)
      .is('deleted_at', null)
      .order('date', { ascending: false })

    // Also get last 3 months for trend context
    const threeMonthsAgo = new Date()
    threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3)
    const { data: historicalTxns } = await supabase
      .from('transactions')
      .select('amount, category, date')
      .eq('household_id', userData.household_id)
      .gte('date', threeMonthsAgo.toISOString().split('T')[0])
      .lt('date', monthStart)
      .is('deleted_at', null)

    // Build spending by category
    const categorySpending: Record<string, number> = {}
    let totalSpent = 0
    ;(transactions ?? []).forEach((t: any) => {
      categorySpending[t.category] = (categorySpending[t.category] || 0) + t.amount
      totalSpent += t.amount
    })

    // Historical monthly averages by category
    const historicalByCategory: Record<string, number[]> = {}
    ;(historicalTxns ?? []).forEach((t: any) => {
      if (!historicalByCategory[t.category]) historicalByCategory[t.category] = []
      historicalByCategory[t.category].push(t.amount)
    })
    const avgByCategory: Record<string, number> = {}
    for (const [cat, amounts] of Object.entries(historicalByCategory)) {
      avgByCategory[cat] = amounts.reduce((a, b) => a + b, 0) / 3
    }

    const budgetComparison = (budgets ?? []).map((b: any) => ({
      category: b.category,
      budgeted: b.amount,
      spent: categorySpending[b.category] || 0,
      pct: b.amount > 0 ? ((categorySpending[b.category] || 0) / b.amount * 100).toFixed(1) : '0',
      avg_last_3m: avgByCategory[b.category]?.toFixed(2) ?? 'N/A',
    }))

    const dataContext = `
Family: ${household.name}
Month: ${currentMonth}
Total spent so far: ₹${totalSpent.toFixed(2)}
Transactions count: ${(transactions ?? []).length}

Budget vs Actual:
${budgetComparison.map((b: any) => `- ${b.category}: ₹${b.spent} / ₹${b.budgeted} (${b.pct}%) | 3-month avg: ₹${b.avg_last_3m}`).join('\n')}

Unbudgeted spending:
${Object.entries(categorySpending).filter(([cat]) => !(budgets ?? []).some((b: any) => b.category === cat)).map(([cat, amt]) => `- ${cat}: ₹${(amt as number).toFixed(2)}`).join('\n') || 'None'}
`

    const messages: ChatMessage[] = [
      {
        role: 'system',
        content: `You are a budget analyst for an Indian family finance app. Analyze the family's budget performance and provide:
1. A brief overall assessment (2-3 sentences)
2. A JSON array of specific suggestions, each with:
   - "category": the budget category
   - "suggestion": actionable advice (1 sentence)
   - "amount_change": suggested budget adjustment in ₹ (positive = increase, negative = decrease, 0 = keep)

Return your response in this EXACT format:
ANALYSIS: <your 2-3 sentence analysis>
SUGGESTIONS: <JSON array>

Rules:
- Use Indian Rupees (₹)
- Be specific and data-driven
- Do NOT give investment advice
- Focus on spending optimization
- Reference actual numbers from the data`,
      },
      {
        role: 'user',
        content: `Analyze this family's budget performance:\n\n${dataContext}`,
      },
    ]

    const result = await routeAIRequest(supabase, 'budget_analysis', messages, {
      max_tokens: 500,
      temperature: 0.5,
    })

    // Parse response
    let analysis = result.content
    let suggestions: any[] = []

    const analysisMatch = result.content.match(/ANALYSIS:\s*([\s\S]*?)(?=SUGGESTIONS:|$)/i)
    const suggestionsMatch = result.content.match(/SUGGESTIONS:\s*(\[[\s\S]*\])/i)

    if (analysisMatch) {
      analysis = analysisMatch[1].trim()
    }
    if (suggestionsMatch) {
      try {
        suggestions = JSON.parse(suggestionsMatch[1])
      } catch {
        suggestions = []
      }
    }

    // Update usage
    await supabase.from('ai_usage').upsert({
      household_id: userData.household_id,
      month: currentMonth,
      budget_analysis_count: used + 1,
    }, { onConflict: 'household_id,month' })

    return new Response(JSON.stringify({
      analysis,
      suggestions,
      total_spent: totalSpent,
      budget_count: (budgets ?? []).length,
      uses_remaining: limit - used - 1,
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('ai-budget-analysis error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
