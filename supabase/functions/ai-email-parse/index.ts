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

    const { email_subject, email_body } = await req.json()

    if (!email_body || typeof email_body !== 'string' || email_body.trim().length === 0) {
      return new Response(JSON.stringify({ error: 'email_body is required' }), {
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

    const subject = typeof email_subject === 'string' ? email_subject.trim() : ''
    // Truncate very long emails to prevent token overuse
    const body = email_body.trim().substring(0, 3000)

    const messages: ChatMessage[] = [
      {
        role: 'system',
        content: `You are a bank email parser for an Indian family finance app. Given a bank notification email (from HDFC, ICICI, SBI, Axis, Kotak, or other Indian banks), extract all transaction details.

Return ONLY a JSON object:
{
  "transactions": [
    {
      "amount": <number in INR>,
      "description": "<merchant or purpose>",
      "category": "<one of: food, transport, utilities, shopping, healthcare, entertainment, other>",
      "date": "<YYYY-MM-DD>",
      "merchant": "<merchant name if available>"
    }
  ]
}

Rules:
- Handle UPI, NEFT, IMPS, debit card, credit card notifications
- "INR", "Rs.", "₹" all mean Indian Rupees
- Extract the actual merchant name (e.g., "Swiggy", "Amazon", "Uber")
- Set category based on merchant
- If multiple transactions in one email, list them all
- If the email is not a transaction notification, return {"transactions": []}
- Return ONLY valid JSON`,
      },
      {
        role: 'user',
        content: `Parse this bank email:\nSubject: ${subject}\n\n${body}`,
      },
    ]

    try {
      const result = await routeAIRequest(supabase, 'email_parsing', messages, {
        max_tokens: 400,
        temperature: 0.1,
      })

      let parsed: { transactions: any[] }
      try {
        const cleaned = result.content.replace(/```json\n?/g, '').replace(/```/g, '').trim()
        parsed = JSON.parse(cleaned)
      } catch {
        parsed = { transactions: [] }
      }

      return new Response(JSON.stringify({
        transactions: parsed.transactions || [],
        model: result.model,
        provider: result.provider,
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    } catch (aiError) {
      console.error('AI email parse error:', aiError)
      return new Response(JSON.stringify({
        transactions: [],
        error: 'AI parsing unavailable — could not extract transactions',
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
  } catch (error) {
    console.error('ai-email-parse error:', error)
    const msg = error instanceof Error ? error.message : 'Internal server error'
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
