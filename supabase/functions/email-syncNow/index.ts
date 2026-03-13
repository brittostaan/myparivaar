import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface EmailSyncRequest {
  email_account_id?: string // specific account, or all if omitted
  days_back?: number // how many days to sync (default 7)
}

interface ParsedTransaction {
  amount: number
  category: string
  description: string
  date: string
  source: 'email'
  email_subject?: string
  confidence: number // 0.0 to 1.0
}

/**
 * Syncs emails from connected accounts and parses them for transactions
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

    // Parse request body
    const { email_account_id, days_back = 7 }: EmailSyncRequest = await req.json().catch(() => ({}))

    // Initialize Supabase client
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: "app" },
    })

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

    // Get email accounts to sync
    let emailAccountsQuery = supabase
      .from('email_accounts')
      .select('*')
      .eq('household_id', userData.household_id)
      .eq('is_active', true)

    if (email_account_id) {
      emailAccountsQuery = emailAccountsQuery.eq('id', email_account_id)
    }

    const { data: emailAccounts, error: emailAccountsError } = await emailAccountsQuery

    if (emailAccountsError || !emailAccounts?.length) {
      return new Response(JSON.stringify({ error: 'No active email accounts found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    let totalSynced = 0
    let totalParsed = 0
    const syncResults = []

    // Process each email account
    for (const account of emailAccounts) {
      try {
        const result = await syncEmailAccount(account, days_back, supabase)
        syncResults.push({
          email: account.email_address,
          provider: account.provider,
          emails_processed: result.emailsProcessed,
          transactions_found: result.transactionsFound
        })
        totalSynced += result.emailsProcessed
        totalParsed += result.transactionsFound
      } catch (error) {
        console.error(`Failed to sync account ${account.email_address}:`, error)
        syncResults.push({
          email: account.email_address,
          provider: account.provider,
          error: error.message
        })
      }
    }

    return new Response(
      JSON.stringify({
        message: 'Email sync completed',
        total_emails_processed: totalSynced,
        total_transactions_found: totalParsed,
        accounts_synced: syncResults
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )

  } catch (error) {
    console.error('email-syncNow error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})

async function syncEmailAccount(account: any, daysBack: number, supabase: any) {
  const cutoffDate = new Date()
  cutoffDate.setDate(cutoffDate.getDate() - daysBack)

  let emails = []
  
  if (account.provider === 'gmail') {
    emails = await fetchGmailMessages(account, cutoffDate)
  } else if (account.provider === 'outlook') {
    emails = await fetchOutlookMessages(account, cutoffDate)
  }

  const parsedTransactions = []
  for (const email of emails) {
    const parsed = parseEmailForTransaction(email)
    if (parsed && parsed.confidence > 0.7) { // Only high-confidence transactions
      parsedTransactions.push(parsed)
    }
  }

  // Store suggested transactions (require approval)
  for (const transaction of parsedTransactions) {
    await supabase.from('transactions').insert({
      household_id: account.household_id,
      amount: transaction.amount,
      category: transaction.category,
      description: transaction.description,
      date: transaction.date,
      source: 'email',
      notes: `From email: ${transaction.email_subject || 'Unknown'}`,
      is_approved: false, // Requires user approval
      confidence_score: transaction.confidence
    })
  }

  return {
    emailsProcessed: emails.length,
    transactionsFound: parsedTransactions.length
  }
}

async function fetchGmailMessages(account: any, cutoffDate: Date) {
  // Refresh token if needed
  if (account.token_expires_at && new Date(account.token_expires_at) <= new Date()) {
    // TODO: Implement token refresh
  }

  const query = `after:${Math.floor(cutoffDate.getTime() / 1000)} (from:bank OR from:paytm OR from:gpay OR from:phonepe OR subject:transaction OR subject:payment OR subject:debit OR subject:credit)`
  
  const response = await fetch(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages?q=${encodeURIComponent(query)}`,
    {
      headers: { Authorization: `Bearer ${account.access_token}` }
    }
  )

  const data = await response.json()
  if (!data.messages) return []

  const messages = []
  for (const message of data.messages.slice(0, 50)) { // Limit to 50 messages
    const messageResponse = await fetch(
      `https://gmail.googleapis.com/gmail/v1/users/me/messages/${message.id}`,
      {
        headers: { Authorization: `Bearer ${account.access_token}` }
      }
    )
    messages.push(await messageResponse.json())
  }

  return messages
}

async function fetchOutlookMessages(account: any, cutoffDate: Date) {
  // Similar implementation for Outlook Graph API
  const filter = `receivedDateTime ge ${cutoffDate.toISOString()}`
  
  const response = await fetch(
    `https://graph.microsoft.com/v1.0/me/messages?$filter=${encodeURIComponent(filter)}&$top=50`,
    {
      headers: { Authorization: `Bearer ${account.access_token}` }
    }
  )

  const data = await response.json()
  return data.value || []
}

function parseEmailForTransaction(email: any): ParsedTransaction | null {
  // Basic email parsing logic (simplified for MVP)
  const subject = email.payload?.headers?.find((h: any) => h.name === 'Subject')?.value || email.subject || ''
  const body = email.payload?.body?.data || email.body || ''
  
  // Look for transaction patterns
  const amountMatch = subject.match(/(?:Rs\.?|INR|₹)\s*([0-9,]+(?:\.[0-9]{2})?)/i) || 
                     body.match(/(?:Rs\.?|INR|₹)\s*([0-9,]+(?:\.[0-9]{2})?)/i)
  
  if (!amountMatch) return null

  const amount = parseFloat(amountMatch[1].replace(/,/g, ''))
  if (amount <= 0 || amount > 1000000) return null

  // Determine category based on keywords
  let category = 'other'
  const text = (subject + ' ' + body).toLowerCase()
  
  if (text.includes('food') || text.includes('restaurant') || text.includes('zomato') || text.includes('swiggy')) {
    category = 'food'
  } else if (text.includes('fuel') || text.includes('petrol') || text.includes('diesel')) {
    category = 'transport'
  } else if (text.includes('shopping') || text.includes('amazon') || text.includes('flipkart')) {
    category = 'shopping'
  } else if (text.includes('electricity') || text.includes('gas') || text.includes('water')) {
    category = 'utilities'
  }

  // Extract date
  const dateStr = email.internalDate ? 
    new Date(parseInt(email.internalDate)).toISOString().split('T')[0] :
    new Date().toISOString().split('T')[0]

  // Calculate confidence based on patterns
  let confidence = 0.5
  if (text.includes('debited') || text.includes('paid') || text.includes('transaction')) {
    confidence += 0.3
  }
  if (text.includes('bank') || text.includes('upi') || text.includes('card')) {
    confidence += 0.2
  }

  return {
    amount,
    category,
    description: subject.substring(0, 100),
    date: dateStr,
    source: 'email',
    email_subject: subject,
    confidence: Math.min(confidence, 1.0)
  }
}