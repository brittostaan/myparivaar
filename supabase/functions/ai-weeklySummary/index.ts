import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const openaiApiKey = Deno.env.get('OPENAI_API_KEY')!

/**
 * Generate weekly AI summary for household finances
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

    // Initialize Supabase client
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: "app" },
    })

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
      .select('id, name, suspended')
      .eq('id', userData.household_id)
      .single()

    if (householdError || household?.suspended) {
      return new Response(JSON.stringify({ error: 'Household suspended or inactive' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const weeklyLimit = 1

    // Check AI usage for current week
    const startOfWeek = new Date()
    startOfWeek.setDate(startOfWeek.getDate() - startOfWeek.getDay())
    startOfWeek.setHours(0, 0, 0, 0)

    const { data: currentWeekUsage } = await supabase
      .from('ai_usage')
      .select('summary_generated_at')
      .eq('household_id', userData.household_id)
      .eq('month', startOfWeek.toISOString().substring(0, 7))
      .maybeSingle()

    const weeklyUsed = currentWeekUsage?.summary_generated_at && new Date(currentWeekUsage.summary_generated_at) >= startOfWeek ? 1 : 0

    if (weeklyUsed >= weeklyLimit) {
      return new Response(JSON.stringify({ 
        error: 'Weekly summary limit reached',
        limit: weeklyLimit,
        used: weeklyUsed
      }), {
        status: 429,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Check if summary was generated recently (within 24 hours)
    const yesterday = new Date()
    yesterday.setDate(yesterday.getDate() - 1)

    const { data: recentSummary } = await supabase
      .from('ai_summaries')
      .select('summary, created_at')
      .eq('household_id', userData.household_id)
      .eq('summary_type', 'weekly')
      .gte('created_at', yesterday.toISOString())
      .order('created_at', { ascending: false })
      .limit(1)
      .single()

    if (recentSummary) {
      return new Response(JSON.stringify({
        summary: recentSummary.summary,
        generated_at: recentSummary.created_at,
        cached: true
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get financial data for the past week
    const oneWeekAgo = new Date()
    oneWeekAgo.setDate(oneWeekAgo.getDate() - 7)

    const { data: transactions } = await supabase
      .from('transactions')
      .select('amount, category, description, date, source')
      .eq('household_id', userData.household_id)
      .gte('date', oneWeekAgo.toISOString().split('T')[0])
      .is('deleted_at', null)
      .order('date', { ascending: false })

    const { data: budgets } = await supabase
      .from('budgets')
      .select('category, amount, month')
      .eq('household_id', userData.household_id)
      .eq('month', new Date().toISOString().substring(0, 7))

    // Generate AI summary
    const summary = await generateFinancialSummary(transactions || [], budgets || [], household.name)

    // Store the summary
    await supabase.from('ai_summaries').insert({
      household_id: userData.household_id,
      summary_type: 'weekly',
      summary,
      data_from: oneWeekAgo.toISOString().split('T')[0],
      data_to: new Date().toISOString().split('T')[0]
    }).then(() => null).catch(() => null)

    // Update usage counter
    await supabase.from('ai_usage').upsert({
      household_id: userData.household_id,
      month: startOfWeek.toISOString().substring(0, 7),
      summary_generated_at: new Date().toISOString()
    }, {
      onConflict: 'household_id,month'
    })

    return new Response(JSON.stringify({
      summary,
      generated_at: new Date().toISOString(),
      cached: false
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    console.error('ai-weeklySummary error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})

async function generateFinancialSummary(transactions: any[], budgets: any[], householdName: string) {
  if (!openaiApiKey) {
    return "AI summary temporarily unavailable. Please check your spending patterns manually."
  }

  // Calculate spending by category
  const categorySpending: { [key: string]: number } = {}
  let totalSpent = 0

  transactions.forEach(t => {
    categorySpending[t.category] = (categorySpending[t.category] || 0) + t.amount
    totalSpent += t.amount
  })

  // Compare with budgets
  const budgetComparison = budgets.map(budget => {
    const spent = categorySpending[budget.category] || 0
    const remaining = budget.amount - spent
    const percentage = budget.amount > 0 ? (spent / budget.amount * 100) : 0
    
    return {
      category: budget.category,
      budgeted: budget.amount,
      spent,
      remaining,
      percentage
    }
  })

  // Create data string for AI
  const dataString = `
Family: ${householdName}
Total spent this week: ₹${totalSpent.toFixed(2)}
Number of transactions: ${transactions.length}

Spending by category:
${Object.entries(categorySpending)
  .sort(([,a], [,b]) => b - a)
  .map(([cat, amount]) => `- ${cat}: ₹${amount.toFixed(2)}`)
  .join('\n')}

Budget comparison:
${budgetComparison
  .map(b => `- ${b.category}: ₹${b.spent} / ₹${b.budgeted} (${b.percentage.toFixed(1)}%)`)
  .join('\n')}

Recent transactions:
${transactions.slice(0, 5)
  .map(t => `- ${t.date}: ₹${t.amount} for ${t.description} (${t.category})`)
  .join('\n')}
`

  try {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-3.5-turbo',
        messages: [
          {
            role: 'system',
            content: `You are a helpful financial insights assistant for Indian families. Provide a brief, friendly weekly spending summary in 3-4 sentences. Focus on spending patterns, budget performance, and general observations. Do NOT give financial advice, predict outcomes, or recommend products. Use Indian Rupees (₹) and be encouraging but realistic.`
          },
          {
            role: 'user',
            content: `Generate a weekly summary for this family's spending:\n\n${dataString}`
          }
        ],
        max_tokens: 300,
        temperature: 0.7
      })
    })

    const data = await response.json()
    
    if (data.choices && data.choices[0]?.message?.content) {
      return data.choices[0].message.content.trim()
    } else {
      throw new Error('Invalid OpenAI response')
    }
  } catch (error) {
    console.error('OpenAI API error:', error)
    
    // Fallback to simple template-based summary
    const topCategory = Object.entries(categorySpending)
      .sort(([,a], [,b]) => b - a)[0]
    
    const overBudgetCategories = budgetComparison
      .filter(b => b.percentage > 100)
      .length

    return `This week, your family spent ₹${totalSpent.toFixed(2)} across ${transactions.length} transactions. ${
      topCategory ? `Most spending was on ${topCategory[0]} (₹${topCategory[1].toFixed(2)}).` : ''
    } ${
      overBudgetCategories > 0 
        ? `You exceeded budget in ${overBudgetCategories} categories.` 
        : 'Your spending stayed within budget limits.'
    } ${
      transactions.length > 0 
        ? 'Keep tracking your expenses to maintain good financial habits!' 
        : 'No transactions recorded this week.'
    }`
  }
}