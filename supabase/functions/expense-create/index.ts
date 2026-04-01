import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface CreateExpenseRequest {
  amount: number
  category: string
  description: string
  date: string // YYYY-MM-DD format
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

/**
 * Create a new expense for the authenticated user's household
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

    // Verify Supabase authentication
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

    // Parse and validate request body
    const { amount, category, description, date, notes, tags }: CreateExpenseRequest = await req.json()

    if (!amount || typeof amount !== 'number' || amount <= 0 || amount > 99999999.99) {
      return new Response(JSON.stringify({ error: 'Invalid amount' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const normalizedCategory = (category || '').trim()
    if (!normalizedCategory || normalizedCategory.length > 50) {
      return new Response(JSON.stringify({ error: 'Category must be 1-50 characters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!description || typeof description !== 'string' || description.trim().length < 1 || description.length > 200) {
      return new Response(JSON.stringify({ error: 'Description must be 1-200 characters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return new Response(JSON.stringify({ error: 'Invalid date format. Use YYYY-MM-DD' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (notes && (typeof notes !== 'string' || notes.length > 500)) {
      return new Response(JSON.stringify({ error: 'Notes cannot exceed 500 characters' }), {
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

    // Initialize Supabase client
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: "app" },
    })

    // Get user's household
    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('household_id')
      .eq('firebase_uid', decodedToken.uid)
      .single()

    if (userError || !userData?.household_id) {
      return new Response(JSON.stringify({ error: 'User not found or not active' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Ensure household exists
    const { data: household, error: householdError } = await supabase
      .from('households')
      .select('id')
      .eq('id', userData.household_id)
      .single()

    if (householdError || !household?.id) {
      return new Response(JSON.stringify({ error: 'Household not found' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Create the expense
    const { data: expense, error: createError } = await supabase
      .from('transactions')
      .insert({
        household_id: userData.household_id,
        amount,
        category: normalizedCategory,
        description: description.trim(),
        date,
        notes: notes?.trim() || null,
        tags: sanitizedTags,
        source: 'manual',
        status: 'approved',
      })
      .select()
      .single()

    if (createError) {
      console.error('Database error:', createError)
      return new Response(JSON.stringify({ error: 'Failed to create expense' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(
      JSON.stringify({ 
        message: 'Expense created successfully',
        expense
      }),
      {
        status: 201,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )

  } catch (error) {
    console.error('expense-create error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})