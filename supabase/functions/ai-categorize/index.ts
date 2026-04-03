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

    const body = await req.json()
    const { description, amount, items } = body

    // ── Batch mode: categorize multiple items at once ──
    if (Array.isArray(items) && items.length > 0) {
      const itemDescriptions = items
        .map((it: { description: string; amount?: number }, i: number) =>
          `${i + 1}. "${it.description}"${it.amount ? ` (₹${it.amount})` : ''}`)
        .join('\n')

      const batchMessages: ChatMessage[] = [
        {
          role: 'system',
          content: `You are a transaction categorizer for an Indian family finance app. Given a numbered list of transaction descriptions, return ONLY a JSON array of objects. Each object must have:
- "index": the 1-based item number
- "category": one of "food", "transport", "utilities", "shopping", "healthcare", "entertainment", "other"
- "confidence": one of "high", "medium", "low"

Rules:
- Groceries, restaurants, coffee, snacks → "food"
- Auto, taxi, bus, train, petrol, fuel → "transport"
- Electricity, water, gas, internet, phone, mobile, recharge, rent, maintenance, EMI → "utilities"
- Clothes, shoes, mall, Amazon, Flipkart → "shopping"
- Doctor, medicine, hospital, pharmacy → "healthcare"
- Movie, cinema, game, party, Netflix, Spotify, yoga, music, classes → "entertainment"
- Everything else → "other"
- Return ONLY the JSON array, no explanation.`,
        },
        {
          role: 'user',
          content: `Categorize these transactions:\n${itemDescriptions}`,
        },
      ]

      try {
        const result = await routeAIRequest(supabase, 'expense_categorization', batchMessages, {
          max_tokens: items.length * 40,
          temperature: 0.1,
        })

        let parsed: Array<{ index: number; category: string; confidence: string }>
        try {
          const cleaned = result.content.replace(/```json\n?/g, '').replace(/```/g, '').trim()
          parsed = JSON.parse(cleaned)
        } catch {
          parsed = []
        }

        // Build a lookup from index to result
        const resultMap = new Map(parsed.map((p) => [p.index, p]))
        const categories = items.map((_: unknown, i: number) => {
          const r = resultMap.get(i + 1)
          return {
            category: r?.category ?? 'other',
            confidence: r?.confidence ?? 'low',
          }
        })

        return new Response(JSON.stringify({
          categories,
          model: result.model,
          provider: result.provider,
        }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      } catch (aiError) {
        // Fallback: local keyword matching for batch
        const keywordMap: Record<string, string[]> = {
          food: ['food', 'restaurant', 'dinner', 'lunch', 'breakfast', 'coffee', 'grocery', 'groceries', 'snack', 'meal', 'swiggy', 'zomato'],
          transport: ['auto', 'taxi', 'bus', 'train', 'metro', 'uber', 'ola', 'rickshaw', 'fuel', 'petrol', 'diesel'],
          utilities: ['electricity', 'water', 'gas', 'internet', 'phone', 'mobile', 'bill', 'recharge', 'rent', 'maintenance', 'emi'],
          shopping: ['shopping', 'clothes', 'shoes', 'amazon', 'flipkart', 'mall', 'myntra'],
          healthcare: ['doctor', 'medicine', 'hospital', 'pharmacy', 'medical', 'health'],
          entertainment: ['movie', 'cinema', 'game', 'party', 'netflix', 'spotify', 'entertainment', 'yoga', 'music', 'class'],
        }

        const categories = items.map((it: { description: string }) => {
          const lower = it.description.toLowerCase()
          let category = 'other'
          for (const [cat, keywords] of Object.entries(keywordMap)) {
            if (keywords.some((kw) => lower.includes(kw))) {
              category = cat
              break
            }
          }
          return { category, confidence: 'low' }
        })

        return new Response(JSON.stringify({ categories, fallback: true }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
    }

    // ── Single item mode (existing) ──
    if (!description || typeof description !== 'string' || description.trim().length === 0) {
      return new Response(JSON.stringify({ error: 'description is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: 'app' },
    })

    // Verify user is active
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

    const amountHint = amount ? ` (amount: ₹${amount})` : ''

    const messages: ChatMessage[] = [
      {
        role: 'system',
        content: `You are a transaction categorizer for an Indian family finance app. Given a transaction description, return ONLY a JSON object with two fields:
- "category": one of "food", "transport", "utilities", "shopping", "healthcare", "entertainment", "other"
- "confidence": one of "high", "medium", "low"

Rules:
- Groceries, restaurants, coffee, snacks → "food"
- Auto, taxi, bus, train, petrol, fuel → "transport"
- Electricity, water, gas, internet, phone, mobile, recharge → "utilities"
- Clothes, shoes, mall, Amazon, Flipkart → "shopping"
- Doctor, medicine, hospital, pharmacy → "healthcare"
- Movie, cinema, game, party, Netflix, Spotify → "entertainment"
- Everything else → "other"
- Return ONLY the JSON object, no explanation.`,
      },
      {
        role: 'user',
        content: `Categorize this transaction: "${description.trim()}"${amountHint}`,
      },
    ]

    try {
      const result = await routeAIRequest(supabase, 'expense_categorization', messages, {
        max_tokens: 50,
        temperature: 0.1,
      })

      // Parse the AI response as JSON
      let parsed: { category: string; confidence: string }
      try {
        const cleaned = result.content.replace(/```json\n?/g, '').replace(/```/g, '').trim()
        parsed = JSON.parse(cleaned)
      } catch {
        // Fallback: try to extract category from plain text
        const lower = result.content.toLowerCase()
        const categories = ['food', 'transport', 'utilities', 'shopping', 'healthcare', 'entertainment']
        const found = categories.find((c) => lower.includes(c)) ?? 'other'
        parsed = { category: found, confidence: 'medium' }
      }

      return new Response(JSON.stringify({
        category: parsed.category,
        confidence: parsed.confidence ?? 'medium',
        model: result.model,
        provider: result.provider,
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    } catch (aiError) {
      // Fallback: local keyword matching
      const lower = description.toLowerCase()
      const keywordMap: Record<string, string[]> = {
        food: ['food', 'restaurant', 'dinner', 'lunch', 'breakfast', 'coffee', 'grocery', 'groceries', 'snack', 'meal', 'swiggy', 'zomato'],
        transport: ['auto', 'taxi', 'bus', 'train', 'metro', 'uber', 'ola', 'rickshaw', 'fuel', 'petrol', 'diesel'],
        utilities: ['electricity', 'water', 'gas', 'internet', 'phone', 'mobile', 'bill', 'recharge'],
        shopping: ['shopping', 'clothes', 'shoes', 'amazon', 'flipkart', 'mall', 'myntra'],
        healthcare: ['doctor', 'medicine', 'hospital', 'pharmacy', 'medical', 'health'],
        entertainment: ['movie', 'cinema', 'game', 'party', 'netflix', 'spotify', 'entertainment'],
      }

      let category = 'other'
      for (const [cat, keywords] of Object.entries(keywordMap)) {
        if (keywords.some((kw) => lower.includes(kw))) {
          category = cat
          break
        }
      }

      return new Response(JSON.stringify({
        category,
        confidence: 'low',
        fallback: true,
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
  } catch (error) {
    console.error('ai-categorize error:', error)
    const msg = error instanceof Error ? error.message : 'Internal server error'
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
