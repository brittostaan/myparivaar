import { json, requireAdmin, getScopedResourceIds } from '../_shared/admin.ts'
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
    const { supabase, scope } = await requireAdmin(req)
    const currentMonth = monthKey(new Date())

    if (scope === 'global') {
      const [householdsRes, subscriptionsRes, usersRes, aiUsageRes, auditRes] = await Promise.all([
        supabase.from('households').select('id', { count: 'exact', head: true }).is('deleted_at', null),
        supabase
          .from('subscriptions')
          .select('id', { count: 'exact', head: true })
          .eq('status', 'active')
          .is('deleted_at', null),
        supabase.from('users').select('id', { count: 'exact', head: true }).is('deleted_at', null),
        supabase.from('ai_usage').select('chat_count').eq('month', currentMonth),
        supabase.from('audit_logs').select('created_at').order('created_at', { ascending: false }).limit(1),
      ])

      if (householdsRes.error || subscriptionsRes.error || usersRes.error || aiUsageRes.error || auditRes.error) {
        console.error('admin-stats global query error:', {
          households: householdsRes.error,
          subscriptions: subscriptionsRes.error,
          users: usersRes.error,
          aiUsage: aiUsageRes.error,
          audit: auditRes.error,
        })
        return json({ error: 'Failed to load admin statistics' }, 500)
      }

      const aiUsageThisMonth = (aiUsageRes.data ?? []).reduce(
        (sum, item) => sum + Number(item.chat_count ?? 0),
        0,
      )

      return json({
        total_households: householdsRes.count ?? 0,
        active_subscriptions: subscriptionsRes.count ?? 0,
        total_users: usersRes.count ?? 0,
        ai_usage_this_month: aiUsageThisMonth,
        last_audit_action: auditRes.data?.[0]?.created_at ?? null,
      })
    }

    const scopedIds = await getScopedResourceIds(supabase, scope)
    const [householdRes, subscriptionsRes, usersRes, aiUsageRes, auditRes] = await Promise.all([
      supabase.from('households').select('id').eq('id', scope).is('deleted_at', null).maybeSingle(),
      supabase
        .from('subscriptions')
        .select('id', { count: 'exact', head: true })
        .eq('household_id', scope)
        .eq('status', 'active')
        .is('deleted_at', null),
      supabase
        .from('users')
        .select('id', { count: 'exact', head: true })
        .eq('household_id', scope)
        .is('deleted_at', null),
      supabase.from('ai_usage').select('chat_count').eq('household_id', scope).eq('month', currentMonth),
      supabase.from('audit_logs').select('resource_type, resource_id, created_at').order('created_at', { ascending: false }).limit(200),
    ])

    if (householdRes.error || subscriptionsRes.error || usersRes.error || aiUsageRes.error || auditRes.error) {
      console.error('admin-stats scoped query error:', {
        household: householdRes.error,
        subscriptions: subscriptionsRes.error,
        users: usersRes.error,
        aiUsage: aiUsageRes.error,
        audit: auditRes.error,
      })
      return json({ error: 'Failed to load admin statistics' }, 500)
    }

    const aiUsageThisMonth = (aiUsageRes.data ?? []).reduce(
      (sum, item) => sum + Number(item.chat_count ?? 0),
      0,
    )

    const lastAuditAction = (auditRes.data ?? []).find((item) => {
      if (item.resource_type === 'household') {
        return item.resource_id === scope
      }
      if (item.resource_type === 'user') {
        return item.resource_id != null && scopedIds.userIds.has(item.resource_id)
      }
      if (item.resource_type === 'subscription') {
        return item.resource_id != null && scopedIds.subscriptionIds.has(item.resource_id)
      }
      return false
    })

    return json({
      total_households: householdRes.data ? 1 : 0,
      active_subscriptions: subscriptionsRes.count ?? 0,
      total_users: usersRes.count ?? 0,
      ai_usage_this_month: aiUsageThisMonth,
      last_audit_action: lastAuditAction?.created_at ?? null,
    })
  } catch (error) {
    if (error instanceof Response) {
      return error
    }

    console.error('admin-stats error:', error)
    return json({ error: 'Internal server error' }, 500)
  }
})