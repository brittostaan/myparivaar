import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface BudgetUpsertRequest {
  category: string
  amount: number
  month: string // YYYY-MM
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

/**
 * Create or update a budget for a category+month.
 * Conflicts on (household_id, category, month) are handled via upsert.
 * If the row was previously soft-deleted, deleted_at is cleared.
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

    const { category, amount, month, tags }: BudgetUpsertRequest = await req.json()

    // Validate inputs
    const normalizedCategory = (category ?? '').toLowerCase().trim()
    if (!normalizedCategory || normalizedCategory.length > 50) {
      return new Response(JSON.stringify({ error: 'Category is required and must be 50 characters or less' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (typeof amount !== 'number' || amount <= 0 || amount > 99999999.99) {
      return new Response(JSON.stringify({ error: 'Invalid amount. Must be a positive number up to 99,999,999.99' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!month || !/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) {
      return new Response(JSON.stringify({ error: 'Invalid month format. Use YYYY-MM' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    let sanitizedTags: string[]
    try {
      sanitizedTags = sanitizeTags(tags)
    } catch (error) {
      return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Invalid tags' }), {
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

    // Upsert: insert or update on conflict (household_id, category, month).
    // Setting deleted_at = null reactivates a previously soft-deleted row.
    const { data: budget, error: upsertError } = await supabase
      .from('budgets')
      .upsert(
        {
          household_id: householdId,
          category: normalizedCategory,
          amount: amount,
          month: month,
          tags: sanitizedTags,
          deleted_at: null,
        },
        { onConflict: 'household_id,category,month' }
      )
      .select()
      .single()

    if (upsertError) {
      console.error('budget-upsert DB error:', upsertError)
      return new Response(JSON.stringify({ error: 'Failed to save budget' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(
      JSON.stringify({ budget: { ...budget, spent: 0 } }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('budget-upsert error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
