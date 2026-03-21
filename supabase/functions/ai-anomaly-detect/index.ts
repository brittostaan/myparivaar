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

    // Rate limit: 2/month
    const currentMonth = new Date().toISOString().substring(0, 7)
    const { data: usage } = await supabase
      .from('ai_usage')
      .select('anomaly_count')
      .eq('household_id', userData.household_id)
      .eq('month', currentMonth)
      .maybeSingle()

    const used = usage?.anomaly_count || 0
    const limit = 2

    if (used >= limit) {
      return new Response(JSON.stringify({
        error: 'Monthly anomaly detection limit reached',
        limit,
        used,
      }), {
        status: 429,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get 90 days of transactions
    const ninetyDaysAgo = new Date()
    ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90)

    const { data: transactions } = await supabase
      .from('transactions')
      .select('amount, category, description, date, source')
      .eq('household_id', userData.household_id)
      .gte('date', ninetyDaysAgo.toISOString().split('T')[0])
      .is('deleted_at', null)
      .order('date', { ascending: false })

    const txns = transactions ?? []

    if (txns.length < 5) {
      return new Response(JSON.stringify({
        anomalies: [],
        summary: 'Not enough transaction data to detect anomalies. Keep tracking your expenses!',
        transaction_count: txns.length,
        uses_remaining: limit - used,
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Calculate statistics for context
    const categoryStats: Record<string, { total: number; count: number; amounts: number[] }> = {}
    let totalSpent = 0

    txns.forEach((t: any) => {
      if (!categoryStats[t.category]) {
        categoryStats[t.category] = { total: 0, count: 0, amounts: [] }
      }
      categoryStats[t.category].total += t.amount
      categoryStats[t.category].count++
      categoryStats[t.category].amounts.push(t.amount)
      totalSpent += t.amount
    })

    const statsContext = Object.entries(categoryStats).map(([cat, s]) => {
      const avg = s.total / s.count
      const max = Math.max(...s.amounts)
      return `- ${cat}: ${s.count} txns, avg ₹${avg.toFixed(0)}, max ₹${max.toFixed(0)}, total ₹${s.total.toFixed(0)}`
    }).join('\n')

    // Recent transactions (last 30 days) for detailed analysis
    const thirtyDaysAgo = new Date()
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)
    const recentTxns = txns.filter((t: any) => new Date(t.date) >= thirtyDaysAgo)

    const recentList = recentTxns.slice(0, 40).map((t: any) =>
      `${t.date}: ₹${t.amount} - ${t.description} [${t.category}]`
    ).join('\n')

    const messages: ChatMessage[] = [
      {
        role: 'system',
        content: `You are a financial anomaly detector for an Indian family finance app. Analyze the transaction history and identify unusual patterns.

Return your response in this EXACT format:
SUMMARY: <2-3 sentence overview of findings>
ANOMALIES: <JSON array of anomalies>

Each anomaly in the JSON array:
{
  "date": "YYYY-MM-DD",
  "amount": <number>,
  "description": "<transaction description>",
  "category": "<category>",
  "reason": "<why this is unusual — 1 sentence>"
}

Look for:
- Transactions significantly above category average (>2x)
- Duplicate or very similar charges on same day
- Unusual categories for the household
- Sudden spending spikes in a week vs previous weeks
- Very large single transactions

If nothing unusual, return ANOMALIES: [] with a positive summary.
Do NOT flag normal daily expenses. Only flag genuinely suspicious or noteworthy items.
Maximum 10 anomalies.`,
      },
      {
        role: 'user',
        content: `Analyze these transactions for anomalies:

Family: ${household.name}
Period: Last 90 days (${txns.length} transactions, total ₹${totalSpent.toFixed(0)})

Category statistics (90-day):
${statsContext}

Recent transactions (last 30 days):
${recentList}`,
      },
    ]

    const result = await routeAIRequest(supabase, 'anomaly_detection', messages, {
      max_tokens: 600,
      temperature: 0.3,
    })

    // Parse response
    let summary = result.content
    let anomalies: any[] = []

    const summaryMatch = result.content.match(/SUMMARY:\s*([\s\S]*?)(?=ANOMALIES:|$)/i)
    const anomaliesMatch = result.content.match(/ANOMALIES:\s*(\[[\s\S]*\])/i)

    if (summaryMatch) summary = summaryMatch[1].trim()
    if (anomaliesMatch) {
      try {
        anomalies = JSON.parse(anomaliesMatch[1])
      } catch {
        anomalies = []
      }
    }

    // Update usage
    await supabase.from('ai_usage').upsert({
      household_id: userData.household_id,
      month: currentMonth,
      anomaly_count: used + 1,
    }, { onConflict: 'household_id,month' })

    return new Response(JSON.stringify({
      summary,
      anomalies,
      transaction_count: txns.length,
      period_days: 90,
      uses_remaining: limit - used - 1,
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('ai-anomaly-detect error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
