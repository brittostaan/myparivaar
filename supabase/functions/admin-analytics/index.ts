import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { isSuperAdmin } from '../_shared/admin.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// ============================================================================
// Types
// ============================================================================

interface AnalyticsOverview {
  period: string
  totalHouseholds: number
  activeSubscriptions: number
  totalUsers: number
  aiUsageThisMonth: number
  churnRateLastMonth: number
}

interface SubscriptionTrend {
  month: string
  activeSubscriptions: number
  newSubscriptions: number
  cancelledSubscriptions: number
  planBreakdown: Record<string, number>
}

interface HouseholdTrend {
  month: string
  newHouseholds: number
  activeHouseholds: number
  suspendedHouseholds: number
}

interface AdminActivitySummary {
  adminId: string
  adminEmail: string
  actionCount: number
  lastActiveAt: string
  topActions: Array<{ action: string; count: number }>
}

interface AIUsageTrend {
  month: string
  totalChatQueries: number
  totalSummariesGenerated: number
  activeUsersThisMonth: number
  averageQueriesPerUser: number
}

// ============================================================================
// Action: get_overview
// ============================================================================

async function getOverview(req: Request) {
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY)
  const { month } = await req.json()

  const currentMonth = month || new Date().toISOString().slice(0, 7)
  const lastMonth = new Date(currentMonth + '-01')
  lastMonth.setMonth(lastMonth.getMonth() - 1)
  const lastMonthStr = lastMonth.toISOString().slice(0, 7)

  // Current month stats
  const [householdsRes, subscriptionsRes, usersRes, aiUsageRes] = await Promise.all([
    supabase.from('households').select('id', { count: 'exact', head: true }).is('deleted_at', null),
    supabase.from('subscriptions').select('id', { count: 'exact', head: true }).eq('status', 'active'),
    supabase.from('users').select('id', { count: 'exact', head: true }).is('deleted_at', null),
    supabase.from('ai_usage').select('chat_count').eq('month', currentMonth),
  ])

  // Last month active subscriptions for churn rate calculation
  const { data: lastMonthSubs } = await supabase
    .from('subscriptions')
    .select('id')
    .eq('status', 'active')
    .gte('created_at', `${lastMonthStr}-01T00:00:00Z`)

  const aiUsageThisMonth = (aiUsageRes.data ?? []).reduce((sum: number, item: any) => sum + Number(item.chat_count ?? 0), 0)
  const currentActiveSubs = subscriptionsRes.count ?? 0
  const lastMonthActiveSubs = lastMonthSubs?.length ?? 0
  const churnRate = lastMonthActiveSubs > 0 ? ((lastMonthActiveSubs - currentActiveSubs) / lastMonthActiveSubs) * 100 : 0

  return new Response(
    JSON.stringify({
      overview: {
        period: currentMonth,
        total_households: householdsRes.count ?? 0,
        active_subscriptions: currentActiveSubs,
        total_users: usersRes.count ?? 0,
        ai_usage_this_month: aiUsageThisMonth,
        churn_rate_last_month: Math.round(churnRate * 100) / 100,
      },
    }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  )
}

// ============================================================================
// Action: get_subscription_trends
// ============================================================================

async function getSubscriptionTrends(req: Request) {
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY)
  const { monthsBack = 12 } = await req.json()
  const trends: SubscriptionTrend[] = []

  for (let i = monthsBack - 1; i >= 0; i--) {
    const date = new Date()
    date.setMonth(date.getMonth() - i)
    const month = date.toISOString().slice(0, 7)
    const monthStart = `${month}-01T00:00:00Z`
    const monthEnd = new Date(date.getFullYear(), date.getMonth() + 1, 1).toISOString().slice(0, 10) + 'T00:00:00Z'

    const { data: subscriptions } = await supabase
      .from('subscriptions')
      .select('id, plan_id, status, created_at, cancelled_at')
      .gte('created_at', monthStart)
      .lt('created_at', monthEnd)

    const active = subscriptions?.filter((s: any) => s.status === 'active').length ?? 0
    const newSubs = subscriptions?.length ?? 0
    const cancelled = subscriptions?.filter((s: any) => s.status === 'cancelled').length ?? 0

    // Get plan breakdown for active subscriptions in this month
    const { data: activePlans } = await supabase
      .from('subscriptions')
      .select('plan_id')
      .eq('status', 'active')
      .lte('created_at', monthEnd)

    const planBreakdown: Record<string, number> = {}
    for (const sub of activePlans ?? []) {
      planBreakdown[sub.plan_id] = (planBreakdown[sub.plan_id] || 0) + 1
    }

    trends.push({
      month,
      activeSubscriptions: active,
      newSubscriptions: newSubs,
      cancelledSubscriptions: cancelled,
      planBreakdown,
    })
  }

  return new Response(JSON.stringify({ trends }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ============================================================================
// Action: get_household_trends
// ============================================================================

async function getHouseholdTrends(req: Request) {
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY)
  const { monthsBack = 12 } = await req.json()
  const trends: HouseholdTrend[] = []

  for (let i = monthsBack - 1; i >= 0; i--) {
    const date = new Date()
    date.setMonth(date.getMonth() - i)
    const month = date.toISOString().slice(0, 7)
    const monthStart = `${month}-01T00:00:00Z`
    const monthEnd = new Date(date.getFullYear(), date.getMonth() + 1, 1).toISOString().slice(0, 10) + 'T00:00:00Z'

    // New households created in this month
    const { count: newCount } = await supabase
      .from('households')
      .select('id', { count: 'exact', head: true })
      .gte('created_at', monthStart)
      .lt('created_at', monthEnd)
      .is('deleted_at', null)

    // Active households at end of this month
    const { count: activeCount } = await supabase
      .from('households')
      .select('id', { count: 'exact', head: true })
      .lt('created_at', monthEnd)
      .is('deleted_at', null)

    // Suspended households at end of this month
    const { count: suspendedCount } = await supabase
      .from('households')
      .select('id', { count: 'exact', head: true })
      .lt('created_at', monthEnd)
      .eq('suspended', true)

    trends.push({
      month,
      newHouseholds: newCount ?? 0,
      activeHouseholds: activeCount ?? 0,
      suspendedHouseholds: suspendedCount ?? 0,
    })
  }

  return new Response(JSON.stringify({ trends }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ============================================================================
// Action: get_admin_activity
// ============================================================================

async function getAdminActivity(req: Request) {
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY)
  const { daysBack = 30 } = await req.json()

  const cutoffDate = new Date()
  cutoffDate.setDate(cutoffDate.getDate() - daysBack)

  const { data: logs } = await supabase
    .from('audit_logs')
    .select('admin_user_id, action, created_at')
    .gte('created_at', cutoffDate.toISOString())
    .order('created_at', { ascending: false })

  // Aggregate by admin
  const adminStats = new Map<string, { actionCount: number; lastActiveAt: string; actions: Map<string, number> }>()

  for (const log of logs ?? []) {
    const adminId = log.admin_user_id as string
    const action = log.action as string
    const created = log.created_at as string

    if (!adminStats.has(adminId)) {
      adminStats.set(adminId, {
        actionCount: 0,
        lastActiveAt: created,
        actions: new Map(),
      })
    }

    const stats = adminStats.get(adminId)!
    stats.actionCount += 1
    if (created > stats.lastActiveAt) {
      stats.lastActiveAt = created
    }
    stats.actions.set(action, (stats.actions.get(action) ?? 0) + 1)
  }

  // Get admin emails
  const adminIds = Array.from(adminStats.keys())
  const { data: admins } = adminIds.length === 0
    ? { data: [] }
    : await supabase.from('users').select('id, email').in('id', adminIds)

  const emailById = new Map((admins ?? []).map((a: any) => [a.id as string, a.email as string]))

  const activity: AdminActivitySummary[] = Array.from(adminStats.entries()).map(([adminId, stats]) => ({
    adminId,
    adminEmail: emailById.get(adminId) ?? 'Unknown',
    actionCount: stats.actionCount,
    lastActiveAt: stats.lastActiveAt,
    topActions: Array.from(stats.actions.entries())
      .map(([action, count]) => ({ action, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 5),
  }))

  return new Response(JSON.stringify({ activity: activity.sort((a, b) => b.actionCount - a.actionCount) }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ============================================================================
// Action: get_ai_usage_trends
// ============================================================================

async function getAIUsageTrends(req: Request) {
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY)
  const { monthsBack = 12 } = await req.json()
  const trends: AIUsageTrend[] = []

  for (let i = monthsBack - 1; i >= 0; i--) {
    const date = new Date()
    date.setMonth(date.getMonth() - i)
    const month = date.toISOString().slice(0, 7)

    const { data: usage } = await supabase.from('ai_usage').select('chat_count, household_id').eq('month', month)

    const totalChats = usage?.reduce((sum: number, u: any) => sum + Number(u.chat_count ?? 0), 0) ?? 0
    const activeUsers = usage?.length ?? 0
    const avgQueries = activeUsers > 0 ? Math.round((totalChats / activeUsers) * 100) / 100 : 0

    // Count summaries generated (heuristic: summaries_generated_at is set)
    const { count: summariesCount } = await supabase
      .from('ai_usage')
      .select('id', { count: 'exact', head: true })
      .eq('month', month)
      .not('summary_generated_at', 'is', null)

    trends.push({
      month,
      totalChatQueries: totalChats,
      totalSummariesGenerated: summariesCount ?? 0,
      activeUsersThisMonth: activeUsers,
      averageQueriesPerUser: avgQueries,
    })
  }

  return new Response(JSON.stringify({ trends }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ============================================================================
// Main Handler
// ============================================================================

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const token = authHeader.replace('Bearer ', '')
    const userResponse = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { Authorization: `Bearer ${token}` },
    })

    if (!userResponse.ok) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const authUser = await userResponse.json()
    const userId = authUser.id

    // Check if super admin (only super admins can access analytics)
    const isSuperAdminUser = await isSuperAdmin(userId, SUPABASE_URL, SERVICE_KEY)

    if (!isSuperAdminUser) {
      return new Response(JSON.stringify({ error: 'Only super admins can access analytics' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { action } = await req.json()

    switch (action) {
      case 'get_overview':
        return getOverview(req)
      case 'get_subscription_trends':
        return getSubscriptionTrends(req)
      case 'get_household_trends':
        return getHouseholdTrends(req)
      case 'get_admin_activity':
        return getAdminActivity(req)
      case 'get_ai_usage_trends':
        return getAIUsageTrends(req)
      default:
        return new Response(JSON.stringify({ error: `Unknown action: ${action}` }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    }
  } catch (error) {
    const msg = error instanceof Error ? error.message : 'Unknown error'
    console.error('admin-analytics error:', msg)
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
