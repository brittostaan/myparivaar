import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface BillsUpsertRequest {
  id?: string
  name: string
  provider?: string
  category: string
  frequency: string
  amount: number
  due_date: string
  is_recurring: boolean
  notes?: string
  tags?: string[]
}

function sanitizeTags(tags?: string[]): string[] {
  if (!Array.isArray(tags)) return []

  const seen = new Set<string>()
  const output: string[] = []

  for (const rawTag of tags) {
    if (typeof rawTag !== 'string') continue
    const normalized = rawTag.trim().replace(/\s+/g, ' ')
    if (!normalized) continue
    if (normalized.length > 40) {
      throw new Error('Each tag must be 40 characters or less')
    }
    const key = normalized.toLowerCase()
    if (!seen.has(key)) {
      seen.add(key)
      output.push(normalized)
    }
  }

  if (output.length > 15) {
    throw new Error('You can add up to 15 tags')
  }

  return output
}

const validCategories = new Set([
  'rent',
  'utilities',
  'internet',
  'insurance',
  'credit_card',
  'subscription',
  'loan',
  'school',
  'other',
])

const validFrequencies = new Set(['monthly', 'quarterly', 'yearly', 'one_time'])

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

    const body: BillsUpsertRequest = await req.json()
    const name = (body.name ?? '').trim()

    let sanitizedTags: string[]
    try {
      sanitizedTags = sanitizeTags(body.tags)
    } catch (error) {
      return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Invalid tags' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!name || name.length > 100) {
      return new Response(JSON.stringify({ error: 'Name is required and must be 1-100 characters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!validCategories.has(body.category)) {
      return new Response(JSON.stringify({ error: 'Invalid category' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!validFrequencies.has(body.frequency)) {
      return new Response(JSON.stringify({ error: 'Invalid frequency' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (typeof body.amount !== 'number' || body.amount <= 0 || body.amount > 99999999.99) {
      return new Response(JSON.stringify({ error: 'Invalid amount' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!/^\d{4}-(0[1-9]|1[0-2])-\d{2}$/.test(body.due_date)) {
      return new Response(JSON.stringify({ error: 'Invalid due_date format. Use YYYY-MM-DD' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: 'app' },
    })

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

    const payload = {
      name,
      provider: body.provider?.trim() || null,
      category: body.category,
      frequency: body.frequency,
      amount: body.amount,
      due_date: body.due_date,
      is_recurring: body.is_recurring,
      notes: body.notes?.trim() || null,
      tags: sanitizedTags,
    }

    if (body.id) {
      const { data: existing, error: existingError } = await supabase
        .from('bills')
        .select('id')
        .eq('id', body.id)
        .eq('household_id', userData.household_id)
        .is('deleted_at', null)
        .single()

      if (existingError || !existing) {
        return new Response(JSON.stringify({ error: 'Bill not found or access denied' }), {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const { data: bill, error: updateError } = await supabase
        .from('bills')
        .update(payload)
        .eq('id', body.id)
        .select()
        .single()

      if (updateError) {
        console.error('bills-upsert update error:', updateError)
        return new Response(JSON.stringify({ error: 'Failed to update bill' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      return new Response(
        JSON.stringify({ bill }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { data: bill, error: insertError } = await supabase
      .from('bills')
      .insert({
        household_id: userData.household_id,
        ...payload,
      })
      .select()
      .single()

    if (insertError) {
      console.error('bills-upsert insert error:', insertError)
      return new Response(JSON.stringify({ error: 'Failed to create bill' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(
      JSON.stringify({ bill }),
      { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('bills-upsert error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
