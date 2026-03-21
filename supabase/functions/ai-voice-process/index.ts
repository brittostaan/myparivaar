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

    const { transcription } = await req.json()

    if (!transcription || typeof transcription !== 'string' || transcription.trim().length === 0) {
      return new Response(JSON.stringify({ error: 'transcription is required' }), {
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

    const messages: ChatMessage[] = [
      {
        role: 'system',
        content: `You are a voice-to-expense parser for an Indian family finance app. Given a voice transcription in English or Hinglish, extract expense details and return ONLY a JSON object:
{
  "amount": <number in INR>,
  "description": "<clean short description>",
  "category": "<one of: food, transport, utilities, shopping, healthcare, entertainment, other>",
  "date": "<YYYY-MM-DD if mentioned, otherwise null>"
}

Rules:
- "rupees", "rs", "₹" all mean Indian Rupees
- "Swiggy", "Zomato" → food
- "Ola", "Uber", "auto", "rickshaw" → transport
- If no date mentioned, set date to null
- Clean up the description: remove filler words, make it concise
- If you cannot determine the amount, set it to 0
- Return ONLY valid JSON, no explanation`,
      },
      {
        role: 'user',
        content: `Parse this voice expense: "${transcription.trim()}"`,
      },
    ]

    try {
      const result = await routeAIRequest(supabase, 'voice_processing', messages, {
        max_tokens: 100,
        temperature: 0.1,
      })

      let parsed: { amount: number; description: string; category: string; date: string | null }
      try {
        const cleaned = result.content.replace(/```json\n?/g, '').replace(/```/g, '').trim()
        parsed = JSON.parse(cleaned)
      } catch {
        // If JSON parsing fails, return a best-effort fallback
        parsed = { amount: 0, description: transcription.trim(), category: 'other', date: null }
      }

      return new Response(JSON.stringify({
        amount: parsed.amount || 0,
        description: parsed.description || transcription.trim(),
        category: parsed.category || 'other',
        date: parsed.date || null,
        model: result.model,
        provider: result.provider,
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    } catch (aiError) {
      // Fallback: basic regex parsing (same as Flutter local logic)
      const text = transcription.toLowerCase()
      const amountMatch = text.match(/(\d+(?:\.\d{1,2})?)\s*(?:rupees?|rs\.?|inr)/i) ||
        text.match(/(\d+(?:\.\d{1,2})?)/)
      const amount = amountMatch ? parseFloat(amountMatch[1]) : 0

      const keywordMap: Record<string, string[]> = {
        food: ['food', 'restaurant', 'dinner', 'lunch', 'breakfast', 'coffee', 'grocery', 'swiggy', 'zomato'],
        transport: ['auto', 'taxi', 'bus', 'train', 'uber', 'ola', 'rickshaw', 'petrol', 'fuel'],
        utilities: ['electricity', 'water', 'gas', 'internet', 'phone', 'bill', 'recharge'],
        shopping: ['shopping', 'clothes', 'shoes', 'amazon', 'flipkart', 'mall'],
        healthcare: ['doctor', 'medicine', 'hospital', 'pharmacy'],
        entertainment: ['movie', 'cinema', 'game', 'party', 'netflix'],
      }

      let category = 'other'
      for (const [cat, kws] of Object.entries(keywordMap)) {
        if (kws.some((kw) => text.includes(kw))) { category = cat; break }
      }

      return new Response(JSON.stringify({
        amount,
        description: transcription.trim(),
        category,
        date: null,
        fallback: true,
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
  } catch (error) {
    console.error('ai-voice-process error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
