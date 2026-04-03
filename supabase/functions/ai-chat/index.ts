import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'
import { routeAIRequest, type ChatMessage } from '../_shared/ai-router.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface ChatRequest {
  message: string
}

/**
 * AI chat endpoint for financial queries with usage limits
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
    const { message }: ChatRequest = await req.json()
    
    if (!message || typeof message !== 'string' || message.trim().length === 0) {
      return new Response(JSON.stringify({ error: 'Message is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (message.length > 500) {
      return new Response(JSON.stringify({ error: 'Message too long (max 500 characters)' }), {
        status: 400,
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

    // Keep a fixed default until plan-based limits are fully standardized.
    const monthlyLimit = 5

    // Check AI usage for current month
    const currentMonth = new Date().toISOString().substring(0, 7)

    const { data: currentUsage } = await supabase
      .from('ai_usage')
      .select('chat_count')
      .eq('household_id', userData.household_id)
      .eq('month', currentMonth)
      .maybeSingle()

    const queriesUsed = currentUsage?.chat_count || 0

    if (queriesUsed >= monthlyLimit) {
      return new Response(JSON.stringify({ 
        error: 'Monthly chat limit reached',
        limit: monthlyLimit,
        used: queriesUsed,
        reset_date: new Date(new Date().getFullYear(), new Date().getMonth() + 1, 1).toISOString().split('T')[0]
      }), {
        status: 429,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get recent financial data for context
    const oneMonthAgo = new Date()
    oneMonthAgo.setMonth(oneMonthAgo.getMonth() - 1)

    const { data: transactions } = await supabase
      .from('transactions')
      .select('amount, category, description, date, source')
      .eq('household_id', userData.household_id)
      .gte('date', oneMonthAgo.toISOString().split('T')[0])
      .is('deleted_at', null)
      .order('date', { ascending: false })
      .limit(50)

    const { data: budgets } = await supabase
      .from('budgets')
      .select('category, amount, month')
      .eq('household_id', userData.household_id)
      .eq('month', currentMonth)

    const { data: savings } = await supabase
      .from('savings_goals')
      .select('name, target_amount, current_amount, target_date')
      .eq('household_id', userData.household_id)
      .eq('is_active', true)

    // Generate AI response
    const response = await generateChatResponse(
      supabase,
      message, 
      transactions || [], 
      budgets || [], 
      savings || [], 
      household.name
    )

    // Store chat interaction
    await supabase.from('ai_chat_history').insert({
      household_id: userData.household_id,
      user_message: message.substring(0, 500), // truncate for storage
      ai_response: response.substring(0, 1000),
      created_by: decodedToken.uid
    }).then(() => null).catch(() => null)

    // Update usage counter
    await supabase.from('ai_usage').upsert({
      household_id: userData.household_id,
      month: currentMonth,
      chat_count: queriesUsed + 1
    }, {
      onConflict: 'household_id,month'
    })

    return new Response(JSON.stringify({
      response,
      queries_remaining: monthlyLimit - queriesUsed - 1,
      queries_used: queriesUsed + 1,
      monthly_limit: monthlyLimit
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    console.error('ai-chat error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})

async function generateChatResponse(
  supabase: ReturnType<typeof createClient>,
  userMessage: string,
  transactions: any[],
  budgets: any[],
  savings: any[],
  householdName: string
): Promise<string> {
  // Calculate spending summaries
  const totalSpent = transactions.reduce((sum, t) => sum + t.amount, 0)
  
  const categorySpending: { [key: string]: number } = {}
  transactions.forEach(t => {
    categorySpending[t.category] = (categorySpending[t.category] || 0) + t.amount
  })

  const budgetSummary = budgets.map(b => ({
    category: b.category,
    budgeted: b.amount,
    spent: categorySpending[b.category] || 0
  }))

  // Create context data
  const contextData = `
Family: ${householdName}
Recent spending (last 30 days): ₹${totalSpent.toFixed(2)}
Number of transactions: ${transactions.length}

Top spending categories:
${Object.entries(categorySpending)
  .sort(([,a], [,b]) => b - a)
  .slice(0, 5)
  .map(([cat, amount]) => `- ${cat}: ₹${amount.toFixed(2)}`)
  .join('\n')}

Current budgets:
${budgetSummary
  .map(b => `- ${b.category}: ₹${b.spent} / ₹${b.budgeted}`)
  .join('\n')}

Savings goals:
${savings
  .map(s => `- ${s.name}: ₹${s.current_amount} / ₹${s.target_amount}`)
  .join('\n')}
`

  const messages: ChatMessage[] = [
    {
      role: 'system',
      content: `You are a helpful financial assistant for Indian families using the myParivaar app. Answer questions about their spending, budgets, and savings based on the provided data. 

IMPORTANT RULES:
- Provide insights and observations only, never financial advice
- Never recommend specific financial products or investments
- Never predict future market performance or outcomes
- Use Indian Rupees (₹) format
- Keep responses under 200 words
- Be encouraging but realistic
- If asked about something not in the data, say you don't have that information
- Focus on spending patterns, budget tracking, and goal progress only`
    },
    {
      role: 'user',
      content: `Based on my family's financial data:\n\n${contextData}\n\nQuestion: ${userMessage}`
    }
  ]

  try {
    const result = await routeAIRequest(supabase, 'financial_chat', messages, {
      max_tokens: 250,
      temperature: 0.7,
    })
    return result.content

  } catch (error) {
    console.error('AI router error:', error)
    
    // Fallback responses based on common question patterns
    const lowerMessage = userMessage.toLowerCase()
    
    if (lowerMessage.includes('spend') || lowerMessage.includes('expense')) {
      if (totalSpent > 0) {
        const topCategory = Object.entries(categorySpending)
          .sort(([,a], [,b]) => b - a)[0]
        return `You've spent ₹${totalSpent.toFixed(2)} in the last month across ${transactions.length} transactions. ${
          topCategory ? `Most spending was on ${topCategory[0]} (₹${topCategory[1].toFixed(2)}).` : ''
        }`
      } else {
        return "I don't see any recent transactions in your account. Start logging your expenses to get better insights!"
      }
    }
    
    if (lowerMessage.includes('budget')) {
      if (budgets.length > 0) {
        const overBudget = budgetSummary.filter(b => b.spent > b.budgeted).length
        return `You have ${budgets.length} budgets set up. ${
          overBudget > 0 
            ? `${overBudget} categories are over budget this month.` 
            : 'All categories are within budget!'
        }`
      } else {
        return "You haven't set up any budgets yet. Consider creating monthly budgets to track your spending better."
      }
    }
    
    if (lowerMessage.includes('save') || lowerMessage.includes('goal')) {
      if (savings.length > 0) {
        return `You have ${savings.length} savings goals. Keep tracking your contributions to reach your targets!`
      } else {
        return "You haven't set up any savings goals yet. Consider creating goals to stay motivated!"
      }
    }
    
    return "I can help you understand your spending patterns, budget performance, and savings progress. Try asking specific questions about your expenses or budgets!"
  }
}