import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface DeleteExpenseRequest {
  expense_id: string
}

/**
 * Delete an expense (soft delete) for the authenticated user's household
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

    // Verify Firebase authentication
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
    const { expense_id }: DeleteExpenseRequest = await req.json()

    if (!expense_id || typeof expense_id !== 'string') {
      return new Response(JSON.stringify({ error: 'Expense ID is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Initialize Supabase client
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Get user's household
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

    // Check household status
    const { data: household, error: householdError } = await supabase
      .from('households')
      .select('is_active, suspended_at')
      .eq('id', userData.household_id)
      .single()

    if (householdError || !household?.is_active || household.suspended_at) {
      return new Response(JSON.stringify({ error: 'Household suspended or inactive' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Verify expense belongs to user's household
    const { data: existingExpense, error: expenseError } = await supabase
      .from('transactions')
      .select('id, household_id')
      .eq('id', expense_id)
      .eq('household_id', userData.household_id)
      .eq('is_active', true)
      .single()

    if (expenseError || !existingExpense) {
      return new Response(JSON.stringify({ error: 'Expense not found or access denied' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Soft delete the expense
    const { error: deleteError } = await supabase
      .from('transactions')
      .update({
        is_active: false,
        deleted_at: new Date().toISOString(),
      })
      .eq('id', expense_id)

    if (deleteError) {
      console.error('Database error:', deleteError)
      return new Response(JSON.stringify({ error: 'Failed to delete expense' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(
      JSON.stringify({ 
        message: 'Expense deleted successfully'
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )

  } catch (error) {
    console.error('expense-delete error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})