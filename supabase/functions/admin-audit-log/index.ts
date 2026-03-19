import {
  getScopedResourceIds,
  isLogVisibleToScope,
  json,
  parseBody,
  requireAdmin,
} from '../_shared/admin.ts'
import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  try {
    const { supabase, scope } = await requireAdmin(req)
    const body = await parseBody(req)
    const requestedLimit = Number(body.limit ?? 50)
    const limit = Number.isFinite(requestedLimit)
      ? Math.max(1, Math.min(200, Math.trunc(requestedLimit)))
      : 50
    const resourceType = typeof body.resource_type === 'string' ? body.resource_type.trim() : null
    const resourceId = typeof body.resource_id === 'string' ? body.resource_id.trim() : null

    let query = supabase
      .from('audit_logs')
      .select('id, admin_user_id, action, resource_type, resource_id, old_values, new_values, description, ip_address, user_agent, created_at')
      .order('created_at', { ascending: false })
      .limit(scope === 'global' ? limit : 200)

    if (resourceType) {
      query = query.eq('resource_type', resourceType)
    }

    if (resourceId) {
      query = query.eq('resource_id', resourceId)
    }

    const { data: logs, error } = await query
    if (error) {
      console.error('admin-audit-log query error:', error)
      return json({ error: 'Failed to fetch audit logs' }, 500)
    }

    let visibleLogs = logs ?? []
    if (scope !== 'global') {
      const scopedIds = await getScopedResourceIds(supabase, scope)
      visibleLogs = visibleLogs
        .filter((log) => isLogVisibleToScope(log, scope, scopedIds))
        .slice(0, limit)
    }

    const adminIds = [...new Set(visibleLogs.map((log) => log.admin_user_id).filter(Boolean))]
    const { data: admins, error: adminsError } = adminIds.length === 0
      ? { data: [], error: null }
      : await supabase
          .from('users')
          .select('id, email')
          .in('id', adminIds)

    if (adminsError) {
      console.error('admin-audit-log admin lookup error:', adminsError)
      return json({ error: 'Failed to fetch admin details' }, 500)
    }

    const emailById = new Map((admins ?? []).map((admin) => [admin.id as string, admin.email as string]))

    return json({
      audit_logs: visibleLogs.map((log) => ({
        ...log,
        admin_email: emailById.get(log.admin_user_id) ?? 'Unknown',
      })),
    })
  } catch (error) {
    if (error instanceof Response) {
      return error
    }

    console.error('admin-audit-log error:', error)
    return json({ error: 'Internal server error' }, 500)
  }
})