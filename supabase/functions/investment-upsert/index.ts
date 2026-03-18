import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface InvestmentUpsertRequest {
  id?: string
  name: string
  type: string
  provider?: string
  amount_invested: number
  current_value: number
  due_date?: string
  maturity_date?: string
  frequency: string
  risk_level: string
  notes?: string
  child_name?: string
}

const validRiskLevels = new Set(['low', 'medium', 'high'])

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

    const body: InvestmentUpsertRequest = await req.json()
    const name = (body.name ?? '').trim()
    const type = (body.type ?? '').trim()

    if (!name || name.length > 120) {
      return new Response(JSON.stringify({ error: 'Name is required and must be 1-120 characters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!type || type.length > 50) {
      return new Response(JSON.stringify({ error: 'Type is required and must be 1-50 characters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (typeof body.amount_invested !== 'number' || body.amount_invested < 0) {
      return new Response(JSON.stringify({ error: 'amount_invested must be a valid non-negative number' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (typeof body.current_value !== 'number' || body.current_value < 0) {
      return new Response(JSON.stringify({ error: 'current_value must be a valid non-negative number' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!validRiskLevels.has(body.risk_level)) {
      return new Response(JSON.stringify({ error: 'risk_level must be low, medium, or high' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (body.due_date && !/^\d{4}-(0[1-9]|1[0-2])-\d{2}$/.test(body.due_date)) {
      return new Response(JSON.stringify({ error: 'Invalid due_date format. Use YYYY-MM-DD' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (body.maturity_date && !/^\d{4}-(0[1-9]|1[0-2])-\d{2}$/.test(body.maturity_date)) {
      return new Response(JSON.stringify({ error: 'Invalid maturity_date format. Use YYYY-MM-DD' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: 'app' },
    })

    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('id, household_id')
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
      type,
      provider: body.provider?.trim() || null,
      amount_invested: body.amount_invested,
      current_value: body.current_value,
      due_date: body.due_date || null,
      maturity_date: body.maturity_date || null,
      frequency: (body.frequency ?? 'One-time').trim(),
      risk_level: body.risk_level,
      notes: body.notes?.trim() || null,
      child_name: body.child_name?.trim() || null,
    }

    if (body.id) {
      const { data: existing, error: existingError } = await supabase
        .from('investments')
        .select('id')
        .eq('id', body.id)
        .eq('household_id', userData.household_id)
        .is('deleted_at', null)
        .single()

      if (existingError || !existing) {
        return new Response(JSON.stringify({ error: 'Investment not found or access denied' }), {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const { data: investment, error: updateError } = await supabase
        .from('investments')
        .update(payload)
        .eq('id', body.id)
        .select()
        .single()

      if (updateError) {
        console.error('investment-upsert update error:', updateError)
        return new Response(JSON.stringify({ error: 'Failed to update investment' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      return new Response(
        JSON.stringify({ investment }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { data: investment, error: insertError } = await supabase
      .from('investments')
      .insert({
        household_id: userData.household_id,
        created_by: userData.id,
        ...payload,
      })
      .select()
      .single()

    if (insertError) {
      console.error('investment-upsert insert error:', insertError)
      return new Response(JSON.stringify({ error: 'Failed to create investment' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(
      JSON.stringify({ investment }),
      { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('investment-upsert error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
