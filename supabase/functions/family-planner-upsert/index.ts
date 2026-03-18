import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface PlannerUpsertRequest {
  id?: string
  item_type: string
  title: string
  description?: string
  start_date: string
  end_date?: string
  is_all_day: boolean
  is_recurring_yearly: boolean
  priority: string
  location?: string
}

const validTypes = new Set(['birthday', 'anniversary', 'vacation', 'event', 'reminder', 'task'])
const validPriorities = new Set(['low', 'medium', 'high'])

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

    const body: PlannerUpsertRequest = await req.json()
    const title = (body.title ?? '').trim()

    if (!validTypes.has(body.item_type)) {
      return new Response(JSON.stringify({ error: 'Invalid item_type' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!title || title.length > 120) {
      return new Response(JSON.stringify({ error: 'Title is required and must be 1-120 characters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!/^\d{4}-(0[1-9]|1[0-2])-\d{2}$/.test(body.start_date)) {
      return new Response(JSON.stringify({ error: 'Invalid start_date format. Use YYYY-MM-DD' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (body.end_date && !/^\d{4}-(0[1-9]|1[0-2])-\d{2}$/.test(body.end_date)) {
      return new Response(JSON.stringify({ error: 'Invalid end_date format. Use YYYY-MM-DD' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!validPriorities.has(body.priority)) {
      return new Response(JSON.stringify({ error: 'Invalid priority' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (typeof body.is_all_day !== 'boolean' || typeof body.is_recurring_yearly !== 'boolean') {
      return new Response(JSON.stringify({ error: 'is_all_day and is_recurring_yearly must be booleans' }), {
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
      item_type: body.item_type,
      title,
      description: body.description?.trim() || null,
      start_date: body.start_date,
      end_date: body.end_date || null,
      is_all_day: body.is_all_day,
      is_recurring_yearly: body.is_recurring_yearly,
      priority: body.priority,
      location: body.location?.trim() || null,
    }

    if (body.id) {
      const { data: existing, error: existingError } = await supabase
        .from('family_planner_items')
        .select('id')
        .eq('id', body.id)
        .eq('household_id', userData.household_id)
        .is('deleted_at', null)
        .single()

      if (existingError || !existing) {
        return new Response(JSON.stringify({ error: 'Planner item not found or access denied' }), {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const { data: item, error: updateError } = await supabase
        .from('family_planner_items')
        .update(payload)
        .eq('id', body.id)
        .select()
        .single()

      if (updateError) {
        console.error('family-planner-upsert update error:', updateError)
        return new Response(JSON.stringify({ error: 'Failed to update planner item' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      return new Response(
        JSON.stringify({ item }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { data: item, error: insertError } = await supabase
      .from('family_planner_items')
      .insert({
        household_id: userData.household_id,
        created_by: userData.id,
        ...payload,
      })
      .select()
      .single()

    if (insertError) {
      console.error('family-planner-upsert insert error:', insertError)
      return new Response(JSON.stringify({ error: 'Failed to create planner item' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(
      JSON.stringify({ item }),
      { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('family-planner-upsert error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
