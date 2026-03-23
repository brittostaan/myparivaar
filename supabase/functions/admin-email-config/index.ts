import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import {
  ADMIN_PERMISSIONS,
  json,
  parseBody,
  requireAdmin,
  writeAuditLog,
} from '../_shared/admin.ts'
import { corsHeaders } from '../_shared/cors.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

function pickClientIp(req: Request): string | null {
  const forwarded = req.headers.get('x-forwarded-for')
  if (!forwarded) return null
  return forwarded.split(',')[0]?.trim() ?? null
}

function normalizeStringList(value: unknown, maxItems: number): string[] {
  if (!Array.isArray(value)) return []

  const cleaned = value
    .map((entry) => String(entry ?? '').trim().toLowerCase())
    .filter((entry) => entry.length > 0)

  return [...new Set(cleaned)].slice(0, maxItems)
}

function isValidEmailAddress(candidate: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(candidate)
}

function currentMonthKey(): string {
  const now = new Date()
  const month = String(now.getUTCMonth() + 1).padStart(2, '0')
  return `${now.getUTCFullYear()}-${month}`
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  try {
    const context = await requireAdmin(req, {
      requiredPermissions: [ADMIN_PERMISSIONS.manageFeatures],
    })
    const { actor, isSuperAdmin } = context

    const supabasePublic = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { persistSession: false },
      db: { schema: 'public' },
    })

    const body = await parseBody(req)
    const action = typeof body.action === 'string' ? body.action.trim() : ''

    if (action === 'list_accounts') {
      const query = typeof body.query === 'string' ? body.query.trim() : ''
      const provider = typeof body.provider === 'string' ? body.provider.trim().toLowerCase() : ''
      const includeInactive = body.include_inactive === true
      const limitRaw = Number(body.limit)
      const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(300, Math.floor(limitRaw))) : 100

      let dbQuery = supabasePublic
        .from('email_accounts')
        .select('id, household_id, email_address, provider, is_active, last_synced_at, created_at, updated_at, screening_sender_filters, screening_keyword_filters, screening_scope_unit, screening_scope_value')
        .order('created_at', { ascending: false })
        .limit(limit)

      if (!isSuperAdmin && actor.household_id != null) {
        dbQuery = dbQuery.eq('household_id', actor.household_id)
      }

      if (!includeInactive) {
        dbQuery = dbQuery.eq('is_active', true)
      }

      if (provider === 'gmail' || provider === 'outlook') {
        dbQuery = dbQuery.eq('provider', provider)
      }

      if (query.length > 0) {
        dbQuery = dbQuery.ilike('email_address', `%${query}%`)
      }

      const { data, error } = await dbQuery
      if (error) {
        console.error('admin-email-config list_accounts error:', error)
        return json({ error: 'Failed to list email accounts' }, 500)
      }

      return json({ accounts: data ?? [] })
    }

    if (action === 'dashboard_summary') {
      let accountsQuery = supabasePublic
        .from('email_accounts')
        .select('id, household_id, provider, is_active, last_synced_at')

      if (!isSuperAdmin && actor.household_id != null) {
        accountsQuery = accountsQuery.eq('household_id', actor.household_id)
      }

      const { data: accounts, error: accountsError } = await accountsQuery
      if (accountsError) {
        console.error('admin-email-config dashboard_summary accounts error:', accountsError)
        return json({ error: 'Failed to load email account summary' }, 500)
      }

      let txQuery = context.supabase
        .from('transactions')
        .select('status')
        .eq('source', 'email')
        .is('deleted_at', null)

      if (!isSuperAdmin && actor.household_id != null) {
        txQuery = txQuery.eq('household_id', actor.household_id)
      }

      const { data: emailTransactions, error: txError } = await txQuery
      if (txError) {
        console.error('admin-email-config dashboard_summary transactions error:', txError)
        return json({ error: 'Failed to load email transaction summary' }, 500)
      }

      let usageQuery = context.supabase
        .from('ai_usage')
        .select('chat_count, budget_analysis_count, anomaly_count, simulator_count, summary_generated_at')
        .eq('month', currentMonthKey())

      if (!isSuperAdmin && actor.household_id != null) {
        usageQuery = usageQuery.eq('household_id', actor.household_id)
      }

      const { data: aiUsageRows, error: usageError } = await usageQuery
      if (usageError) {
        console.error('admin-email-config dashboard_summary ai_usage error:', usageError)
        return json({ error: 'Failed to load AI usage summary' }, 500)
      }

      const accountRows = accounts ?? []
      const transactions = emailTransactions ?? []
      const usage = aiUsageRows ?? []

      const providerCounts: Record<string, number> = { gmail: 0, outlook: 0 }
      const connectedHouseholds = new Set<string>()
      let activeConnections = 0

      for (const row of accountRows) {
        const provider = String(row.provider ?? '').toLowerCase()
        if (provider === 'gmail' || provider === 'outlook') {
          providerCounts[provider] = (providerCounts[provider] ?? 0) + 1
        }
        if (row.is_active === true) {
          activeConnections += 1
        }
        const hid = String(row.household_id ?? '')
        if (hid.length > 0) {
          connectedHouseholds.add(hid)
        }
      }

      let identifiedCount = 0
      let approvedCount = 0
      let pendingCount = 0
      let rejectedCount = 0

      for (const row of transactions) {
        identifiedCount += 1
        const status = String(row.status ?? '').toLowerCase()
        if (status === 'approved') approvedCount += 1
        if (status === 'pending') pendingCount += 1
        if (status === 'rejected') rejectedCount += 1
      }

      let aiRequestCount = 0
      for (const row of usage) {
        aiRequestCount += Number(row.chat_count ?? 0)
        aiRequestCount += Number(row.budget_analysis_count ?? 0)
        aiRequestCount += Number(row.anomaly_count ?? 0)
        aiRequestCount += Number(row.simulator_count ?? 0)
        if (row.summary_generated_at != null) {
          aiRequestCount += 1
        }
      }

      return json({
        summary: {
          total_connected_accounts: accountRows.length,
          active_connections: activeConnections,
          connected_households: connectedHouseholds.size,
          provider_counts: providerCounts,
          emails_scanned: null,
          emails_identified: identifiedCount,
          email_transactions: {
            approved: approvedCount,
            pending: pendingCount,
            rejected: rejectedCount,
          },
          ai_classification_requests_current_month: aiRequestCount,
          ai_tokens_used_current_month: null,
        },
      })
    }

    if (action === 'update_screening') {
      const accountId = typeof body.account_id === 'string' ? body.account_id.trim() : ''
      if (!accountId) {
        return json({ error: 'account_id is required' }, 400)
      }

      const senderFilters = normalizeStringList(body.screening_sender_filters, 50)
      const invalidSender = senderFilters.find((entry) => !isValidEmailAddress(entry)) ?? ''
      if (invalidSender.length > 0) {
        return json({ error: `Invalid sender email: ${invalidSender}` }, 400)
      }

      const keywordFilters = normalizeStringList(body.screening_keyword_filters, 50)
      const scopeUnitRaw = typeof body.screening_scope_unit === 'string' ? body.screening_scope_unit.trim().toLowerCase() : 'days'
      const scopeUnit = scopeUnitRaw === 'months' ? 'months' : 'days'
      const scopeValueRaw = Number(body.screening_scope_value)
      const defaultScopeValue = scopeUnit === 'months' ? 1 : 7
      const scopeValue = Number.isFinite(scopeValueRaw) ? Math.max(1, Math.min(365, Math.floor(scopeValueRaw))) : defaultScopeValue
      const isActive = typeof body.is_active === 'boolean' ? body.is_active : null

      let currentQuery = supabasePublic
        .from('email_accounts')
        .select('id, household_id, email_address, provider, is_active, screening_sender_filters, screening_keyword_filters, screening_scope_unit, screening_scope_value')
        .eq('id', accountId)
        .maybeSingle()

      if (!isSuperAdmin && actor.household_id != null) {
        currentQuery = currentQuery.eq('household_id', actor.household_id)
      }

      const { data: existing, error: existingError } = await currentQuery
      if (existingError) {
        console.error('admin-email-config update lookup error:', existingError)
        return json({ error: 'Failed to load email account' }, 500)
      }
      if (!existing) {
        return json({ error: 'Email account not found' }, 404)
      }

      const updatePayload: Record<string, unknown> = {
        screening_sender_filters: senderFilters,
        screening_keyword_filters: keywordFilters,
        screening_scope_unit: scopeUnit,
        screening_scope_value: scopeValue,
      }
      if (isActive != null) {
        updatePayload.is_active = isActive
      }

      let updateQuery = supabasePublic
        .from('email_accounts')
        .update(updatePayload)
        .eq('id', accountId)
        .select('id, household_id, email_address, provider, is_active, last_synced_at, created_at, updated_at, screening_sender_filters, screening_keyword_filters, screening_scope_unit, screening_scope_value')
        .maybeSingle()

      if (!isSuperAdmin && actor.household_id != null) {
        updateQuery = updateQuery.eq('household_id', actor.household_id)
      }

      const { data: updated, error: updateError } = await updateQuery
      if (updateError || !updated) {
        console.error('admin-email-config update_screening error:', updateError)
        return json({ error: 'Failed to update screening settings' }, 500)
      }

      await writeAuditLog(context.supabase, {
        adminUserId: actor.id,
        action: 'update_email_screening',
        resourceType: 'email_account',
        resourceId: String(updated.id),
        oldValues: {
          screening_sender_filters: existing.screening_sender_filters,
          screening_keyword_filters: existing.screening_keyword_filters,
          screening_scope_unit: existing.screening_scope_unit,
          screening_scope_value: existing.screening_scope_value,
          is_active: existing.is_active,
        },
        newValues: {
          screening_sender_filters: updated.screening_sender_filters,
          screening_keyword_filters: updated.screening_keyword_filters,
          screening_scope_unit: updated.screening_scope_unit,
          screening_scope_value: updated.screening_scope_value,
          is_active: updated.is_active,
        },
        description: `Updated screening settings for ${updated.email_address}`,
        ipAddress: pickClientIp(req),
        userAgent: req.headers.get('user-agent'),
      })

      return json({ account: updated })
    }

    if (action === 'inbox_insights') {
      // Fetch all accounts with token/sync metadata
      let insightsQuery = supabasePublic
        .from('email_accounts')
        .select('id, household_id, email_address, provider, is_active, access_token, token_expires_at, last_synced_at, created_at, updated_at, screening_sender_filters, screening_keyword_filters, screening_scope_unit, screening_scope_value')
        .order('created_at', { ascending: false })

      if (!isSuperAdmin && actor.household_id != null) {
        insightsQuery = insightsQuery.eq('household_id', actor.household_id)
      }

      const { data: allAccounts, error: insightsError } = await insightsQuery
      if (insightsError) {
        console.error('admin-email-config inbox_insights error:', insightsError)
        return json({ error: 'Failed to load inbox insights' }, 500)
      }

      const now = Date.now()
      const DAY_MS = 86400_000
      let healthyCount = 0
      let staleCount = 0
      let neverSyncedCount = 0
      let expiredTokenCount = 0
      let expiringSoonCount = 0
      let totalSyncAgeMs = 0
      let syncedAccountCount = 0

      const accounts = (allAccounts ?? []).map((row: any) => {
        const lastSynced = row.last_synced_at ? new Date(row.last_synced_at).getTime() : null
        const tokenExpiry = row.token_expires_at ? new Date(row.token_expires_at).getTime() : null

        // Sync health
        let syncHealth: 'healthy' | 'stale' | 'critical' | 'never' = 'never'
        let syncAgeMs: number | null = null
        if (lastSynced) {
          syncAgeMs = now - lastSynced
          syncedAccountCount++
          totalSyncAgeMs += syncAgeMs
          if (syncAgeMs < DAY_MS) {
            syncHealth = 'healthy'
            healthyCount++
          } else if (syncAgeMs < 7 * DAY_MS) {
            syncHealth = 'stale'
            staleCount++
          } else {
            syncHealth = 'critical'
            staleCount++
          }
        } else {
          neverSyncedCount++
        }

        // Token health
        let tokenStatus: 'valid' | 'expiring_soon' | 'expired' | 'unknown' = 'unknown'
        let tokenDaysRemaining: number | null = null
        if (tokenExpiry) {
          const remaining = tokenExpiry - now
          tokenDaysRemaining = Math.floor(remaining / DAY_MS)
          if (remaining <= 0) {
            tokenStatus = 'expired'
            expiredTokenCount++
          } else if (remaining < 7 * DAY_MS) {
            tokenStatus = 'expiring_soon'
            expiringSoonCount++
          } else {
            tokenStatus = 'valid'
          }
        } else if (row.access_token) {
          tokenStatus = 'valid' // has token but no expiry tracked
        }

        return {
          id: row.id,
          household_id: row.household_id,
          email_address: row.email_address,
          provider: row.provider,
          is_active: row.is_active,
          last_synced_at: row.last_synced_at,
          token_expires_at: row.token_expires_at,
          has_access_token: !!row.access_token,
          sync_health: syncHealth,
          sync_age_hours: syncAgeMs != null ? Math.floor(syncAgeMs / 3600_000) : null,
          token_status: tokenStatus,
          token_days_remaining: tokenDaysRemaining,
          filter_count: (row.screening_sender_filters?.length ?? 0) + (row.screening_keyword_filters?.length ?? 0),
          screening_scope: `${row.screening_scope_value ?? 7} ${row.screening_scope_unit ?? 'days'}`,
          created_at: row.created_at,
          updated_at: row.updated_at,
        }
      })

      return json({
        insights: {
          total_accounts: accounts.length,
          healthy_accounts: healthyCount,
          stale_accounts: staleCount,
          never_synced: neverSyncedCount,
          expired_tokens: expiredTokenCount,
          expiring_soon_tokens: expiringSoonCount,
          needs_attention: staleCount + neverSyncedCount + expiredTokenCount,
          average_sync_age_hours: syncedAccountCount > 0 ? Math.floor(totalSyncAgeMs / syncedAccountCount / 3600_000) : null,
        },
        accounts,
      })
    }

    return json({ error: `Unknown action: ${action}` }, 400)
  } catch (thrown) {
    if (thrown instanceof Response) return thrown
    const message = thrown instanceof Error ? thrown.message : 'Unexpected error'
    console.error('admin-email-config error:', message)
    return json({ error: message }, 500)
  }
})
