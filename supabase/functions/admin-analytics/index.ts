import {
  ADMIN_PERMISSIONS,
  json,
  parseBody,
  requireAdmin,
} from '../_shared/admin.ts'
import { corsHeaders } from '../_shared/cors.ts'

function monthKey(date: Date): string {
  const month = `${date.getUTCMonth() + 1}`.padStart(2, '0')
  return `${date.getUTCFullYear()}-${month}`
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
      requiredPermissions: [ADMIN_PERMISSIONS.viewAnalytics],
    })
    const { supabase } = context
    const body = await parseBody(req)
    const action = typeof body.action === 'string' ? body.action.trim() : ''

    // ── get_overview ─────────────────────────────────────────────────────
    if (action === 'get_overview') {
      const currentMonth = typeof body.month === 'string' ? body.month.trim() : monthKey(new Date())

      const [householdsRes, subscriptionsRes, usersRes, aiUsageRes] = await Promise.all([
        supabase.from('households').select('id', { count: 'exact', head: true }).is('deleted_at', null),
        supabase.from('subscriptions').select('id', { count: 'exact', head: true }).eq('status', 'active'),
        supabase.from('users').select('id', { count: 'exact', head: true }).is('deleted_at', null),
        supabase.from('ai_usage').select('chat_count').eq('month', currentMonth),
      ])

      if (householdsRes.error) console.error('households error:', householdsRes.error)
      if (subscriptionsRes.error) console.error('subscriptions error:', subscriptionsRes.error)
      if (usersRes.error) console.error('users error:', usersRes.error)
      if (aiUsageRes.error) console.error('ai_usage error:', aiUsageRes.error)

      const aiUsageThisMonth = (aiUsageRes.data ?? []).reduce(
        (sum: number, item: Record<string, unknown>) => sum + Number(item.chat_count ?? 0), 0,
      )

      return json({
        overview: {
          period: currentMonth,
          total_households: householdsRes.count ?? 0,
          active_subscriptions: subscriptionsRes.count ?? 0,
          total_users: usersRes.count ?? 0,
          ai_usage_this_month: aiUsageThisMonth,
          churn_rate_last_month: 0,
        },
      })
    }

    // ── get_subscription_trends ──────────────────────────────────────────
    if (action === 'get_subscription_trends') {
      const monthsBack = typeof body.monthsBack === 'number' ? body.monthsBack : 12
      const trends = []

      for (let i = monthsBack - 1; i >= 0; i--) {
        const date = new Date()
        date.setMonth(date.getMonth() - i)
        const month = monthKey(date)
        const monthStart = `${month}-01T00:00:00Z`
        const nextMonth = new Date(date.getFullYear(), date.getMonth() + 1, 1)
        const monthEnd = nextMonth.toISOString()

        const [activeRes, newRes, cancelledRes] = await Promise.all([
          supabase.from('subscriptions').select('id', { count: 'exact', head: true })
            .eq('status', 'active').lte('created_at', monthEnd),
          supabase.from('subscriptions').select('id', { count: 'exact', head: true })
            .gte('created_at', monthStart).lt('created_at', monthEnd),
          supabase.from('subscriptions').select('id', { count: 'exact', head: true })
            .eq('status', 'cancelled').gte('cancelled_at', monthStart).lt('cancelled_at', monthEnd),
        ])

        trends.push({
          month,
          activeSubscriptions: activeRes.count ?? 0,
          newSubscriptions: newRes.count ?? 0,
          cancelledSubscriptions: cancelledRes.count ?? 0,
          planBreakdown: {},
        })
      }

      return json({ trends })
    }

    // ── get_household_trends ─────────────────────────────────────────────
    if (action === 'get_household_trends') {
      const monthsBack = typeof body.monthsBack === 'number' ? body.monthsBack : 12
      const trends = []

      for (let i = monthsBack - 1; i >= 0; i--) {
        const date = new Date()
        date.setMonth(date.getMonth() - i)
        const month = monthKey(date)
        const monthStart = `${month}-01T00:00:00Z`
        const nextMonth = new Date(date.getFullYear(), date.getMonth() + 1, 1)
        const monthEnd = nextMonth.toISOString()

        const [newRes, activeRes, suspendedRes] = await Promise.all([
          supabase.from('households').select('id', { count: 'exact', head: true })
            .gte('created_at', monthStart).lt('created_at', monthEnd).is('deleted_at', null),
          supabase.from('households').select('id', { count: 'exact', head: true })
            .lt('created_at', monthEnd).is('deleted_at', null),
          supabase.from('households').select('id', { count: 'exact', head: true })
            .lt('created_at', monthEnd).eq('suspended', true),
        ])

        trends.push({
          month,
          newHouseholds: newRes.count ?? 0,
          activeHouseholds: activeRes.count ?? 0,
          suspendedHouseholds: suspendedRes.count ?? 0,
        })
      }

      return json({ trends })
    }

    // ── get_admin_activity ───────────────────────────────────────────────
    if (action === 'get_admin_activity') {
      const daysBack = typeof body.daysBack === 'number' ? body.daysBack : 30
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
        const logAction = log.action as string
        const created = log.created_at as string

        if (!adminStats.has(adminId)) {
          adminStats.set(adminId, { actionCount: 0, lastActiveAt: created, actions: new Map() })
        }

        const stats = adminStats.get(adminId)!
        stats.actionCount += 1
        if (created > stats.lastActiveAt) stats.lastActiveAt = created
        stats.actions.set(logAction, (stats.actions.get(logAction) ?? 0) + 1)
      }

      // Get admin emails
      const adminIds = Array.from(adminStats.keys())
      const { data: admins } = adminIds.length === 0
        ? { data: [] }
        : await supabase.from('users').select('id, email').in('id', adminIds)

      const emailById = new Map((admins ?? []).map((a: Record<string, unknown>) => [a.id as string, a.email as string]))

      const activity = Array.from(adminStats.entries()).map(([adminId, stats]) => ({
        adminId,
        adminEmail: emailById.get(adminId) ?? 'Unknown',
        actionCount: stats.actionCount,
        lastActiveAt: stats.lastActiveAt,
        topActions: Array.from(stats.actions.entries())
          .map(([a, count]) => ({ action: a, count }))
          .sort((a, b) => b.count - a.count)
          .slice(0, 5),
      }))

      return json({ activity: activity.sort((a, b) => b.actionCount - a.actionCount) })
    }

    // ── get_ai_usage_trends ──────────────────────────────────────────────
    if (action === 'get_ai_usage_trends') {
      const monthsBack = typeof body.monthsBack === 'number' ? body.monthsBack : 12
      const trends = []

      for (let i = monthsBack - 1; i >= 0; i--) {
        const date = new Date()
        date.setMonth(date.getMonth() - i)
        const month = monthKey(date)

        const { data: usage } = await supabase.from('ai_usage').select('chat_count, household_id').eq('month', month)

        const totalChats = (usage ?? []).reduce((sum: number, u: Record<string, unknown>) => sum + Number(u.chat_count ?? 0), 0)
        const activeUsers = usage?.length ?? 0
        const avgQueries = activeUsers > 0 ? Math.round((totalChats / activeUsers) * 100) / 100 : 0

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

      return json({ trends })
    }

    return json({ error: `Unknown action: ${action}` }, 400)
  } catch (thrown) {
    if (thrown instanceof Response) return thrown
    const msg = thrown instanceof Error ? thrown.message : 'Unexpected error'
    console.error('admin-analytics error:', msg)
    return json({ error: msg }, 500)
  }
})
