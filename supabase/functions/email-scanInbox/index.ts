import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'
import { getOAuthCredentials } from '../_shared/oauth.ts'
import { routeAIRequest, type ChatMessage } from '../_shared/ai-router.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

/**
 * Email Inbox Scanning — folder discovery, scan with AI/regex, dedup, results tracking.
 *
 * Actions:
 *   list_folders  – list Gmail labels / Outlook folders for an account
 *   scan          – scan selected folders, extract transactions, track results
 *   scan_status   – get status of a scan run
 *   scan_history  – list past scan results for an account
 */
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    if (req.method !== 'POST') {
      return jsonResponse({ error: 'Method not allowed' }, 405)
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return jsonResponse({ error: 'Missing authorization header' }, 401)
    }

    const idToken = authHeader.split('Bearer ')[1]
    const decodedToken = await verifyFirebaseToken(idToken)
    if (!decodedToken?.uid) {
      return jsonResponse({ error: 'Invalid auth token' }, 401)
    }

    const body = await req.json().catch(() => ({}))
    const action = String(body.action ?? '')

    const supabase = createClient(supabaseUrl, supabaseServiceKey, { db: { schema: 'app' } })
    const supabasePublic = createClient(supabaseUrl, supabaseServiceKey, { db: { schema: 'public' } })

    // Resolve user + household
    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('id, household_id, is_active')
      .eq('firebase_uid', decodedToken.uid)
      .eq('is_active', true)
      .single()

    if (userError || !userData?.household_id) {
      return jsonResponse({ error: 'User not found or not active' }, 404)
    }

    // ── list_folders ─────────────────────────────────────────────────────────
    if (action === 'list_folders') {
      const accountId = String(body.email_account_id ?? '')
      if (!accountId) return jsonResponse({ error: 'email_account_id is required' }, 400)

      const account = await getAccountForHousehold(supabasePublic, accountId, userData.household_id)
      if (!account) return jsonResponse({ error: 'Email account not found' }, 404)

      // Refresh token if needed
      await ensureFreshToken(account, supabasePublic)

      let folders: any[] = []
      if (account.provider === 'gmail') {
        folders = await listGmailLabels(account)
      } else {
        folders = await listOutlookFolders(account)
      }

      return jsonResponse({ folders })
    }

    // ── scan ─────────────────────────────────────────────────────────────────
    if (action === 'scan') {
      const accountId = String(body.email_account_id ?? '')
      if (!accountId) return jsonResponse({ error: 'email_account_id is required' }, 400)

      const account = await getAccountForHousehold(supabasePublic, accountId, userData.household_id)
      if (!account) return jsonResponse({ error: 'Email account not found' }, 404)

      const folderIds: string[] = Array.isArray(body.folder_ids) ? body.folder_ids : []
      const useAi: boolean = body.use_ai !== false
      const daysBack: number = Math.min(Math.max(Number(body.days_back) || 7, 1), 365)

      // Refresh token
      await ensureFreshToken(account, supabasePublic)

      // Create scan result record
      const { data: scanResult, error: scanErr } = await supabasePublic
        .from('email_scan_results')
        .insert({
          email_account_id: accountId,
          status: 'scanning',
          use_ai: useAi,
          folders_scanned: [],
        })
        .select('id')
        .single()

      if (scanErr || !scanResult) {
        console.error('Failed to create scan result:', scanErr)
        return jsonResponse({ error: 'Failed to start scan' }, 500)
      }

      const scanId = scanResult.id

      try {
        const result = await runScan(account, folderIds, daysBack, useAi, scanId, supabase, supabasePublic)

        // Mark completed
        await supabasePublic
          .from('email_scan_results')
          .update({
            status: 'completed',
            folders_scanned: result.foldersScanned,
            total_emails_scanned: result.totalEmails,
            total_transactions_found: result.totalTransactions,
            scan_completed_at: new Date().toISOString(),
          })
          .eq('id', scanId)

        // Update last_synced_at
        await supabasePublic
          .from('email_accounts')
          .update({ last_synced_at: new Date().toISOString() })
          .eq('id', account.id)

        return jsonResponse({
          scan_id: scanId,
          status: 'completed',
          ...result,
        })
      } catch (error: any) {
        // Mark failed
        await supabasePublic
          .from('email_scan_results')
          .update({
            status: 'failed',
            error_message: error.message || String(error),
            scan_completed_at: new Date().toISOString(),
          })
          .eq('id', scanId)

        throw error
      }
    }

    // ── scan_status ──────────────────────────────────────────────────────────
    if (action === 'scan_status') {
      const scanId = String(body.scan_id ?? '')
      if (!scanId) return jsonResponse({ error: 'scan_id is required' }, 400)

      const { data, error } = await supabasePublic
        .from('email_scan_results')
        .select('*, email_accounts!inner(household_id)')
        .eq('id', scanId)
        .eq('email_accounts.household_id', userData.household_id)
        .single()

      if (error || !data) return jsonResponse({ error: 'Scan result not found' }, 404)

      return jsonResponse({ scan: data })
    }

    // ── scan_history ─────────────────────────────────────────────────────────
    if (action === 'scan_history') {
      const accountId = String(body.email_account_id ?? '')
      if (!accountId) return jsonResponse({ error: 'email_account_id is required' }, 400)

      const { data, error } = await supabasePublic
        .from('email_scan_results')
        .select('id, status, folders_scanned, total_emails_scanned, total_transactions_found, use_ai, error_message, scan_started_at, scan_completed_at')
        .eq('email_account_id', accountId)
        .order('scan_started_at', { ascending: false })
        .limit(20)

      if (error) return jsonResponse({ error: 'Failed to fetch scan history' }, 500)

      return jsonResponse({ scans: data ?? [] })
    }

    return jsonResponse({ error: `Unknown action: ${action}` }, 400)

  } catch (error: any) {
    console.error('email-scanInbox error:', error)
    return jsonResponse({ error: error.message || 'Internal server error' }, 500)
  }
})

// ── Helpers ──────────────────────────────────────────────────────────────────

function jsonResponse(data: any, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

async function getAccountForHousehold(supabasePublic: any, accountId: string, householdId: string) {
  const { data, error } = await supabasePublic
    .from('email_accounts')
    .select('*')
    .eq('id', accountId)
    .eq('household_id', householdId)
    .eq('is_active', true)
    .single()
  if (error) return null
  return data
}

async function ensureFreshToken(account: any, supabasePublic: any) {
  const expiresAt = account.token_expires_at ? new Date(account.token_expires_at) : null
  if (expiresAt && expiresAt.getTime() - Date.now() < 5 * 60 * 1000) {
    const provider = account.provider === 'gmail' ? 'google' : 'microsoft'
    const creds = await getOAuthCredentials(provider as 'google' | 'microsoft')
    if (!creds) throw new Error(`OAuth credentials not configured for ${provider}`)
    if (!account.refresh_token) throw new Error('No refresh token — user must re-authenticate')

    let tokenUrl: string
    const params: Record<string, string> = {
      client_id: creds.clientId,
      client_secret: creds.clientSecret,
      refresh_token: account.refresh_token,
      grant_type: 'refresh_token',
    }

    if (provider === 'google') {
      tokenUrl = 'https://oauth2.googleapis.com/token'
    } else {
      tokenUrl = 'https://login.microsoftonline.com/common/oauth2/v2.0/token'
      params.scope = 'https://graph.microsoft.com/Mail.Read https://graph.microsoft.com/User.Read offline_access'
    }

    const resp = await fetch(tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(params),
    })
    const data = await resp.json()

    if (!data.access_token) {
      throw new Error(`Token refresh failed: ${data.error ?? 'unknown'} - ${data.error_description ?? ''}`)
    }

    const newExpiry = data.expires_in
      ? new Date(Date.now() + data.expires_in * 1000).toISOString()
      : null

    await supabasePublic
      .from('email_accounts')
      .update({
        access_token: data.access_token,
        refresh_token: data.refresh_token || account.refresh_token,
        token_expires_at: newExpiry,
      })
      .eq('id', account.id)

    account.access_token = data.access_token
    console.log(`[scanInbox] Refreshed token for ${account.email_address}`)
  }
}

// ── Folder Listing ───────────────────────────────────────────────────────────

async function listGmailLabels(account: any) {
  const resp = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/labels', {
    headers: { Authorization: `Bearer ${account.access_token}` },
  })
  const data = await resp.json()
  if (!data.labels) return []

  // Filter to useful labels only (skip internal system labels)
  const skipIds = new Set(['CHAT', 'DRAFT', 'STARRED', 'UNREAD', 'IMPORTANT'])
  return data.labels
    .filter((l: any) => !skipIds.has(l.id))
    .map((l: any) => ({
      id: l.id,
      name: l.name,
      type: l.type === 'system' ? 'system' : 'user',
      message_count: l.messagesTotal ?? 0,
      unread_count: l.messagesUnread ?? 0,
    }))
}

async function listOutlookFolders(account: any) {
  const resp = await fetch('https://graph.microsoft.com/v1.0/me/mailFolders?$top=50', {
    headers: { Authorization: `Bearer ${account.access_token}` },
  })
  const data = await resp.json()
  if (!data.value) return []

  return data.value.map((f: any) => ({
    id: f.id,
    name: f.displayName,
    type: ['Inbox', 'SentItems', 'Drafts', 'DeletedItems', 'JunkEmail'].includes(f.displayName) ? 'system' : 'user',
    message_count: f.totalItemCount ?? 0,
    unread_count: f.unreadItemCount ?? 0,
  }))
}

// ── Scan Execution ───────────────────────────────────────────────────────────

interface FolderScanResult {
  id: string
  name: string
  emails_found: number
  transactions_found: number
}

async function runScan(
  account: any,
  folderIds: string[],
  daysBack: number,
  useAi: boolean,
  scanId: string,
  supabase: any,
  supabasePublic: any,
) {
  const cutoffDate = new Date()
  cutoffDate.setDate(cutoffDate.getDate() - daysBack)

  // If no folders specified, use INBOX
  if (folderIds.length === 0) {
    folderIds = account.provider === 'gmail' ? ['INBOX'] : ['Inbox']
  }

  const foldersScanned: FolderScanResult[] = []
  let totalEmails = 0
  let totalTransactions = 0

  for (const folderId of folderIds) {
    let messages: any[] = []
    let folderName = folderId

    if (account.provider === 'gmail') {
      const result = await fetchGmailFolderMessages(account, folderId, cutoffDate)
      messages = result.messages
      folderName = result.folderName || folderId
    } else {
      const result = await fetchOutlookFolderMessages(account, folderId, cutoffDate)
      messages = result.messages
      folderName = result.folderName || folderId
    }

    let folderTxCount = 0

    for (const msg of messages) {
      const providerId = msg.id || msg.messageId || ''
      if (!providerId) continue

      // Check dedup — skip already scanned emails
      const { data: existing } = await supabasePublic
        .from('email_scanned_emails')
        .select('id')
        .eq('email_account_id', account.id)
        .eq('provider_message_id', providerId)
        .maybeSingle()

      if (existing) continue

      const subject = extractSubject(msg, account.provider)
      const sender = extractSender(msg, account.provider)
      const receivedAt = extractDate(msg, account.provider)
      const body = extractBody(msg, account.provider)

      let hasTx = false
      let txId: string | null = null
      let aiClassified = false

      if (useAi) {
        // AI classification
        try {
          const aiResult = await classifyWithAI(supabase, subject, body)
          aiClassified = true
          if (aiResult.length > 0) {
            hasTx = true
            // Insert first transaction (most emails have one)
            for (const tx of aiResult) {
              const { data: inserted } = await supabase.from('transactions').insert({
                household_id: account.household_id,
                amount: tx.amount,
                category: tx.category,
                description: tx.description || subject.substring(0, 100),
                date: tx.date || receivedAt?.toISOString().split('T')[0] || new Date().toISOString().split('T')[0],
                source: 'email',
                notes: `AI-classified from ${account.email_address} [${folderName}]`,
                status: 'pending',
              }).select('id').single()
              if (!txId && inserted) txId = inserted.id
            }
          }
        } catch (aiErr: any) {
          console.warn(`AI classify failed for ${providerId}:`, aiErr.message)
          // Fall back to regex
          const regexResult = parseEmailRegex(subject, body, receivedAt)
          if (regexResult) {
            hasTx = true
            const { data: inserted } = await supabase.from('transactions').insert({
              household_id: account.household_id,
              amount: regexResult.amount,
              category: regexResult.category,
              description: regexResult.description,
              date: regexResult.date,
              source: 'email',
              notes: `Regex-parsed from ${account.email_address} [${folderName}] (confidence: ${Math.round(regexResult.confidence * 100)}%)`,
              status: 'pending',
            }).select('id').single()
            if (inserted) txId = inserted.id
          }
        }
      } else {
        // Regex only
        const regexResult = parseEmailRegex(subject, body, receivedAt)
        if (regexResult && regexResult.confidence > 0.7) {
          hasTx = true
          const { data: inserted } = await supabase.from('transactions').insert({
            household_id: account.household_id,
            amount: regexResult.amount,
            category: regexResult.category,
            description: regexResult.description,
            date: regexResult.date,
            source: 'email',
            notes: `Regex-parsed from ${account.email_address} [${folderName}] (confidence: ${Math.round(regexResult.confidence * 100)}%)`,
            status: 'pending',
          }).select('id').single()
          if (inserted) txId = inserted.id
        }
      }

      // Record scanned email
      await supabasePublic.from('email_scanned_emails').insert({
        email_account_id: account.id,
        scan_result_id: scanId,
        provider_message_id: providerId,
        subject: (subject || '').substring(0, 500),
        sender: (sender || '').substring(0, 500),
        received_at: receivedAt?.toISOString() || null,
        folder_name: folderName,
        has_transaction: hasTx,
        transaction_id: txId,
        ai_classified: aiClassified,
      }).catch(() => {}) // ignore duplicate constraint violations

      if (hasTx) folderTxCount++
      totalEmails++
    }

    foldersScanned.push({
      id: folderId,
      name: folderName,
      emails_found: messages.length,
      transactions_found: folderTxCount,
    })
    totalTransactions += folderTxCount
  }

  return { foldersScanned, totalEmails, totalTransactions }
}

// ── Gmail Folder Fetch ───────────────────────────────────────────────────────

async function fetchGmailFolderMessages(account: any, labelId: string, cutoffDate: Date) {
  const query = `after:${Math.floor(cutoffDate.getTime() / 1000)}`
  const url = `https://gmail.googleapis.com/gmail/v1/users/me/messages?q=${encodeURIComponent(query)}&labelIds=${encodeURIComponent(labelId)}&maxResults=100`

  const resp = await fetch(url, {
    headers: { Authorization: `Bearer ${account.access_token}` },
  })
  const data = await resp.json()
  if (!data.messages) return { messages: [], folderName: labelId }

  // Fetch message details (cap at 100)
  const messageIds = data.messages.slice(0, 100)
  const messages: any[] = []

  for (const m of messageIds) {
    const msgResp = await fetch(
      `https://gmail.googleapis.com/gmail/v1/users/me/messages/${m.id}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date`,
      { headers: { Authorization: `Bearer ${account.access_token}` } },
    )
    if (msgResp.ok) {
      const msg = await msgResp.json()
      messages.push(msg)
    }
  }

  return { messages, folderName: labelId }
}

// ── Outlook Folder Fetch ─────────────────────────────────────────────────────

async function fetchOutlookFolderMessages(account: any, folderId: string, cutoffDate: Date) {
  const filter = `receivedDateTime ge ${cutoffDate.toISOString()}`
  const url = `https://graph.microsoft.com/v1.0/me/mailFolders/${encodeURIComponent(folderId)}/messages?$filter=${encodeURIComponent(filter)}&$top=100&$select=id,subject,from,receivedDateTime,bodyPreview`

  const resp = await fetch(url, {
    headers: { Authorization: `Bearer ${account.access_token}` },
  })
  const data = await resp.json()

  let folderName = folderId
  // Try to resolve folder name
  try {
    const folderResp = await fetch(`https://graph.microsoft.com/v1.0/me/mailFolders/${encodeURIComponent(folderId)}`, {
      headers: { Authorization: `Bearer ${account.access_token}` },
    })
    const folderData = await folderResp.json()
    if (folderData.displayName) folderName = folderData.displayName
  } catch {}

  return { messages: data.value || [], folderName }
}

// ── Extract helpers ──────────────────────────────────────────────────────────

function extractSubject(msg: any, provider: string): string {
  if (provider === 'gmail') {
    return msg.payload?.headers?.find((h: any) => h.name === 'Subject')?.value || ''
  }
  return msg.subject || ''
}

function extractSender(msg: any, provider: string): string {
  if (provider === 'gmail') {
    return msg.payload?.headers?.find((h: any) => h.name === 'From')?.value || ''
  }
  return msg.from?.emailAddress?.address || ''
}

function extractDate(msg: any, provider: string): Date | null {
  if (provider === 'gmail') {
    return msg.internalDate ? new Date(parseInt(msg.internalDate)) : null
  }
  return msg.receivedDateTime ? new Date(msg.receivedDateTime) : null
}

function extractBody(msg: any, provider: string): string {
  if (provider === 'gmail') {
    // For metadata-only fetch, snippet is the best we get
    return msg.snippet || ''
  }
  return msg.bodyPreview || ''
}

// ── AI Classification ────────────────────────────────────────────────────────

async function classifyWithAI(supabase: any, subject: string, body: string): Promise<any[]> {
  const text = `${subject}\n\n${body}`.substring(0, 3000)

  const messages: ChatMessage[] = [
    {
      role: 'system',
      content: `You are a bank email parser for an Indian family finance app. Given a bank notification email, extract all transaction details.

Return ONLY a JSON object:
{
  "transactions": [
    {
      "amount": <number in INR>,
      "description": "<merchant or purpose>",
      "category": "<one of: food, transport, utilities, shopping, healthcare, entertainment, other>",
      "date": "<YYYY-MM-DD>",
      "merchant": "<merchant name if available>"
    }
  ]
}

Rules:
- Handle UPI, NEFT, IMPS, debit card, credit card notifications
- "INR", "Rs.", "₹" all mean Indian Rupees
- If the email is NOT a financial transaction notification, return {"transactions": []}
- Return ONLY valid JSON, no markdown`,
    },
    {
      role: 'user',
      content: `Parse this email:\nSubject: ${subject}\n\n${body}`,
    },
  ]

  const result = await routeAIRequest(supabase, 'email_parsing', messages, {
    max_tokens: 400,
    temperature: 0.1,
  })

  try {
    const cleaned = result.content.replace(/```json\n?/g, '').replace(/```/g, '').trim()
    const parsed = JSON.parse(cleaned)
    return parsed.transactions || []
  } catch {
    return []
  }
}

// ── Regex Classification (fallback) ──────────────────────────────────────────

function parseEmailRegex(subject: string, body: string, receivedAt: Date | null) {
  const text = (subject + ' ' + body).toLowerCase()

  const amountMatch = text.match(/(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.[0-9]{2})?)/i)
  if (!amountMatch) return null

  const amount = parseFloat(amountMatch[1].replace(/,/g, ''))
  if (amount <= 0 || amount > 1000000) return null

  let category = 'other'
  if (text.includes('food') || text.includes('restaurant') || text.includes('zomato') || text.includes('swiggy')) {
    category = 'food'
  } else if (text.includes('fuel') || text.includes('petrol') || text.includes('diesel') || text.includes('uber') || text.includes('ola')) {
    category = 'transport'
  } else if (text.includes('shopping') || text.includes('amazon') || text.includes('flipkart') || text.includes('myntra')) {
    category = 'shopping'
  } else if (text.includes('electricity') || text.includes('gas') || text.includes('water') || text.includes('bill')) {
    category = 'utilities'
  }

  let confidence = 0.5
  if (text.includes('debited') || text.includes('paid') || text.includes('transaction') || text.includes('credited')) {
    confidence += 0.3
  }
  if (text.includes('bank') || text.includes('upi') || text.includes('card') || text.includes('neft')) {
    confidence += 0.2
  }

  return {
    amount,
    category,
    description: subject.substring(0, 100) || 'Email transaction',
    date: receivedAt?.toISOString().split('T')[0] || new Date().toISOString().split('T')[0],
    confidence: Math.min(confidence, 1.0),
  }
}
