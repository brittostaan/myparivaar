import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface SavingsContributeRequest {
  goal_id: string
  amount: number   // positive = add funds; negative = withdraw funds
}

/**
 * Add or withdraw a contribution to/from a savings goal.
 * Updates current_amount by the given delta.
 * Ensures current_amount never goes below 0.
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

    const { goal_id, amount }: SavingsContributeRequest = await req.json()

    if (!goal_id || typeof goal_id !== 'string') {
      return new Response(JSON.stringify({ error: 'goal_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (typeof amount !== 'number' || amount === 0 || Math.abs(amount) > 99999999.99) {
      return new Response(JSON.stringify({ error: 'amount must be a non-zero number up to 99,999,999.99' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
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

    // Fetch the goal to verify ownership and get current amount
    const { data: existing, error: fetchError } = await supabase
      .from('savings_goals')
      .select('id, household_id, current_amount')
      .eq('id', goal_id)
      .eq('household_id', householdId)
      .is('deleted_at', null)
      .single()

    if (fetchError || !existing) {
      return new Response(JSON.stringify({ error: 'Savings goal not found or access denied' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const newAmount = Math.max(0, Number(existing.current_amount) + amount)

    const { data: goal, error: updateError } = await supabase
      .from('savings_goals')
      .update({ current_amount: newAmount })
      .eq('id', goal_id)
      .select()
      .single()

    if (updateError) {
      console.error('savings-contribute DB error:', updateError)
      return new Response(JSON.stringify({ error: 'Failed to update savings goal' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(
      JSON.stringify({ goal }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('savings-contribute error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
