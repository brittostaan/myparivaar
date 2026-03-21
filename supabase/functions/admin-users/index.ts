import {
  ADMIN_PERMISSIONS,
  json,
  parseBody,
  requireAdmin,
  requireAdminPermissions,
  writeAuditLog,
} from '../_shared/admin.ts'
import { corsHeaders } from '../_shared/cors.ts'

const USER_LIST_COLS =
  'id, email, display_name, role, staff_role, staff_scope, household_id, is_active, created_at'

const USER_DETAIL_COLS =
  'id, email, display_name, first_name, last_name, phone, date_of_birth, photo_url, role, staff_role, staff_scope, household_id, is_active, notifications_enabled, voice_enabled, created_at, updated_at'

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
        .select(`${USER_LIST_COLS}, households!users_household_id_fkey(name)`)
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

    if (action === 'toggle_active') {
      await requireAdminPermissions(context, [ADMIN_PERMISSIONS.manageUsers])

      const userId = typeof body.user_id === 'string' ? body.user_id.trim() : ''
      const isActive = typeof body.is_active === 'boolean' ? body.is_active : null

      if (!userId || isActive === null) {
        return json({ error: 'user_id and is_active are required' }, 400)
      }

      const { data: existingUser, error: lookupError } = await supabase
        .from('users')
        .select(USER_LIST_COLS)
        .eq('id', userId)
        .is('deleted_at', null)
        .maybeSingle()

      if (lookupError) {
        console.error('admin-users toggle_active lookup error:', lookupError)
        return json({ error: 'Failed to find user' }, 500)
      }

      if (!existingUser) {
        return json({ error: 'User not found' }, 404)
      }

      if (existingUser.role === 'super_admin' || existingUser.staff_role === 'super_admin') {
        return json({ error: 'Cannot modify super admin status' }, 403)
      }

      const { data: updatedUser, error: updateError } = await supabase
        .from('users')
        .update({ is_active: isActive })
        .eq('id', userId)
        .select(USER_LIST_COLS)
        .single()

      if (updateError) {
        console.error('admin-users toggle_active update error:', updateError)
        return json({ error: 'Failed to update user status' }, 500)
      }

      const ipAddress = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? null
      const userAgent = req.headers.get('user-agent')

      await writeAuditLog(supabase, {
        adminUserId: context.actor.id,
        action: isActive ? 'unsuspend' : 'suspend',
        resourceType: 'user',
        resourceId: userId,
        oldValues: { is_active: existingUser.is_active },
        newValues: { is_active: isActive },
        description: `${isActive ? 'Enabled' : 'Disabled'} user ${existingUser.email ?? userId}`,
        ipAddress,
        userAgent,
      })

      return json({
        user: {
          id: updatedUser.id,
          email: updatedUser.email,
          display_name: updatedUser.display_name,
          role: updatedUser.role,
          staff_role: updatedUser.staff_role,
          staff_scope: updatedUser.staff_scope,
          is_active: updatedUser.is_active,
          household_id: updatedUser.household_id,
          created_at: updatedUser.created_at,
        },
      })
    }

    if (action === 'get_user') {
      const userId = typeof body.user_id === 'string' ? body.user_id.trim() : ''
      if (!userId) {
        return json({ error: 'user_id is required' }, 400)
      }

      const { data: user, error } = await supabase
        .from('users')
        .select(`${USER_DETAIL_COLS}, households!users_household_id_fkey(name)`)
        .eq('id', userId)
        .is('deleted_at', null)
        .maybeSingle()

      if (error) {
        console.error('admin-users get_user error:', error)
        return json({ error: 'Failed to fetch user' }, 500)
      }

      if (!user) {
        return json({ error: 'User not found' }, 404)
      }

      return json({
        user: {
          ...user,
          household_name: (user.households as { name?: string } | null)?.name ?? null,
          households: undefined,
        },
      })
    }

    if (action === 'update_user') {
      await requireAdminPermissions(context, [ADMIN_PERMISSIONS.manageUsers])

      const userId = typeof body.user_id === 'string' ? body.user_id.trim() : ''
      if (!userId) {
        return json({ error: 'user_id is required' }, 400)
      }

      const { data: existingUser, error: lookupError } = await supabase
        .from('users')
        .select(USER_DETAIL_COLS)
        .eq('id', userId)
        .is('deleted_at', null)
        .maybeSingle()

      if (lookupError) {
        console.error('admin-users update_user lookup error:', lookupError)
        return json({ error: 'Failed to find user' }, 500)
      }

      if (!existingUser) {
        return json({ error: 'User not found' }, 404)
      }

      if (existingUser.role === 'super_admin' || existingUser.staff_role === 'super_admin') {
        return json({ error: 'Cannot modify super admin profile' }, 403)
      }

      const updates: Record<string, unknown> = {}
      const oldValues: Record<string, unknown> = {}

      const allowedFields = [
        'first_name', 'last_name', 'display_name', 'phone',
        'date_of_birth', 'photo_url', 'notifications_enabled', 'voice_enabled',
      ] as const

      for (const field of allowedFields) {
        if (field in body && body[field] !== undefined) {
          const newVal = body[field]
          if (typeof newVal === 'string') {
            updates[field] = newVal.trim() || null
          } else if (typeof newVal === 'boolean') {
            updates[field] = newVal
          } else if (newVal === null) {
            updates[field] = null
          }
          oldValues[field] = existingUser[field as keyof typeof existingUser]
        }
      }

      if (Object.keys(updates).length === 0) {
        return json({ error: 'No valid fields to update' }, 400)
      }

      const { data: updatedUser, error: updateError } = await supabase
        .from('users')
        .update(updates)
        .eq('id', userId)
        .select(USER_DETAIL_COLS)
        .single()

      if (updateError) {
        console.error('admin-users update_user error:', updateError)
        return json({ error: 'Failed to update user' }, 500)
      }

      const ipAddress = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? null
      const userAgent = req.headers.get('user-agent')

      await writeAuditLog(supabase, {
        adminUserId: context.actor.id,
        action: 'update',
        resourceType: 'user',
        resourceId: userId,
        oldValues,
        newValues: updates,
        description: `Updated profile for ${existingUser.email ?? userId}`,
        ipAddress,
        userAgent,
      })

      return json({ user: updatedUser })
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
