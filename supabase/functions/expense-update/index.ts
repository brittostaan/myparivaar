import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface UpdateExpenseRequest {
  expense_id: string
  amount: number
  category: string
  description: string
  date: string // YYYY-MM-DD format
  notes?: string
}

/**
 * Update an existing expense for the authenticated user's household
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
    const { expense_id, amount, category, description, date, notes }: UpdateExpenseRequest = await req.json()

    if (!expense_id || typeof expense_id !== 'string') {
      return new Response(JSON.stringify({ error: 'Expense ID is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!amount || typeof amount !== 'number' || amount <= 0 || amount > 99999999.99) {
      return new Response(JSON.stringify({ error: 'Invalid amount' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const normalizedCategory = (category || '').toLowerCase().trim()
    const validCategories = ['food', 'transport', 'shopping', 'utilities', 'healthcare', 'entertainment', 'education', 'other']
    if (!normalizedCategory || !validCategories.includes(normalizedCategory)) {
      return new Response(JSON.stringify({ error: 'Invalid category' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!description || typeof description !== 'string' || description.trim().length < 3 || description.length > 100) {
      return new Response(JSON.stringify({ error: 'Description must be 3-100 characters' }), {
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

    if (notes && (typeof notes !== 'string' || notes.length > 200)) {
      return new Response(JSON.stringify({ error: 'Notes cannot exceed 200 characters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Initialize Supabase client
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

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

    // Verify expense belongs to user's household
    const { data: existingExpense, error: expenseError } = await supabase
      .from('transactions')
      .select('id, household_id, source')
      .eq('id', expense_id)
      .eq('household_id', userData.household_id)
      .single()

    if (expenseError || !existingExpense) {
      return new Response(JSON.stringify({ error: 'Expense not found or access denied' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Prevent editing email-sourced transactions
    if (existingExpense.source === 'email') {
      return new Response(JSON.stringify({ error: 'Email-sourced transactions cannot be edited' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Update the expense
    const { data: expense, error: updateError } = await supabase
      .from('transactions')
      .update({
        amount,
        category: normalizedCategory,
        description: description.trim(),
        date,
        notes: notes?.trim() || null,
      })
      .eq('id', expense_id)
      .select()
      .single()

    if (updateError) {
      console.error('Database error:', updateError)
      return new Response(JSON.stringify({ error: 'Failed to update expense' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(
      JSON.stringify({ 
        message: 'Expense updated successfully',
        expense
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )

  } catch (error) {
    console.error('expense-update error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})