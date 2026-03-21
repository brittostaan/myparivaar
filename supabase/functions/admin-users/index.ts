import {
  ADMIN_PERMISSIONS,
  json,
  parseBody,
  requireAdmin,
  requireAdminPermissions,
} from '../_shared/admin.ts'
import { corsHeaders } from '../_shared/cors.ts'

const USER_COLS =
  'id, email, display_name, role, staff_role, staff_scope, household_id, is_active, created_at'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  try {
    const context = await requireAdmin(req, {
      requiredPermissions: [ADMIN_PERMISSIONS.viewUsers],
    })
    await requireAdminPermissions(context, [ADMIN_PERMISSIONS.viewUsers])

    const { supabase } = context
    const body = await parseBody(req)
    const action = typeof body.action === 'string' ? body.action.trim() : 'list'

    if (action === 'list') {
      const query = typeof body.query === 'string' ? body.query.trim() : ''
      const role = typeof body.role === 'string' ? body.role.trim() : ''
      const limit = typeof body.limit === 'number' ? Math.min(body.limit, 500) : 100

      let dbQuery = supabase
        .from('users')
        .select(`${USER_COLS}, households!users_household_id_fkey(name)`)
        .is('deleted_at', null)
        .order('created_at', { ascending: false })
        .limit(limit)

      if (query) {
        dbQuery = dbQuery.or(`email.ilike.%${query}%,display_name.ilike.%${query}%`)
      }

      if (role) {
        dbQuery = dbQuery.eq('role', role)
      }

      const householdId = typeof body.household_id === 'string' ? body.household_id.trim() : ''
      if (householdId) {
        dbQuery = dbQuery.eq('household_id', householdId)
      }

      const { data: users, error } = await dbQuery

      if (error) {
        console.error('admin-users list error:', error)
        return json({ error: 'Failed to list users' }, 500)
      }

      const result = (users ?? []).map((u) => ({
        id: u.id,
        email: u.email,
        display_name: u.display_name,
        role: u.role,
        staff_role: u.staff_role,
        staff_scope: u.staff_scope,
        is_active: u.is_active,
        household_id: u.household_id,
        household_name: (u.households as { name?: string } | null)?.name ?? null,
        created_at: u.created_at,
      }))

      return json({ users: result, total: result.length })
    }

    return json({ error: 'Unsupported action' }, 400)
  } catch (error) {
    if (error instanceof Response) {
      return error
    }

    console.error('admin-users error:', error)
    return json({ error: 'Internal server error' }, 500)
  }
})
