import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface SavingsUpsertRequest {
  id?: string        // omit to create; provide to update
  name: string
  target_amount: number
  target_date?: string  // ISO date YYYY-MM-DD, optional
  notes?: string
}

/**
 * Create or update a savings goal for the authenticated user's household.
 * When `id` is provided, the existing goal is updated (ownership verified).
 * When `id` is omitted, a new goal is created.
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

    const { id, name, target_amount, target_date, notes }: SavingsUpsertRequest = await req.json()

    // Validate name
    const trimmedName = (name ?? '').trim()
    if (!trimmedName || trimmedName.length > 100) {
      return new Response(JSON.stringify({ error: 'Name is required and must be 1–100 characters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Validate target_amount
    if (typeof target_amount !== 'number' || target_amount <= 0 || target_amount > 99999999.99) {
      return new Response(JSON.stringify({ error: 'Invalid target amount. Must be a positive number up to 99,999,999.99' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Validate target_date if provided
    if (target_date !== undefined && target_date !== null) {
      if (!/^\d{4}-(0[1-9]|1[0-2])-\d{2}$/.test(target_date)) {
        return new Response(JSON.stringify({ error: 'Invalid target_date format. Use YYYY-MM-DD' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: 'app' },
    })

    // Resolve household
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

    const householdId = userData.household_id

    if (id) {
      // UPDATE: verify ownership first
      const { data: existing, error: fetchError } = await supabase
        .from('savings_goals')
        .select('id, household_id')
        .eq('id', id)
        .eq('household_id', householdId)
        .is('deleted_at', null)
        .single()

      if (fetchError || !existing) {
        return new Response(JSON.stringify({ error: 'Savings goal not found or access denied' }), {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const { data: goal, error: updateError } = await supabase
        .from('savings_goals')
        .update({
          name: trimmedName,
          target_amount,
          target_date: target_date ?? null,
          notes: notes ?? null,
        })
        .eq('id', id)
        .select()
        .single()

      if (updateError) {
        console.error('savings-upsert update error:', updateError)
        return new Response(JSON.stringify({ error: 'Failed to update savings goal' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      return new Response(
        JSON.stringify({ goal }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    } else {
      // CREATE
      const { data: goal, error: insertError } = await supabase
        .from('savings_goals')
        .insert({
          household_id: householdId,
          name: trimmedName,
          target_amount,
          current_amount: 0,
          target_date: target_date ?? null,
          notes: notes ?? null,
        })
        .select()
        .single()

      if (insertError) {
        console.error('savings-upsert insert error:', insertError)
        return new Response(JSON.stringify({ error: 'Failed to create savings goal' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      return new Response(
        JSON.stringify({ goal }),
        { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }
  } catch (error) {
    console.error('savings-upsert error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
