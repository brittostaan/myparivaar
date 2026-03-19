import { json, parseBody, requireAdmin, writeAuditLog } from '../_shared/admin.ts'
import { corsHeaders } from '../_shared/cors.ts'

const STAFF_COLS = 'id, email, display_name, staff_role, staff_scope, admin_permissions, created_at, role'

function pickClientIp(req: Request): string | null {
  const forwarded = req.headers.get('x-forwarded-for')
  if (!forwarded) {
    return null
  }
  return forwarded.split(',')[0]?.trim() ?? null
}

async function validateScope(supabase: ReturnType<typeof requireAdmin> extends Promise<infer T> ? T['supabase'] : never, scope: string): Promise<void> {
  if (scope === 'global') {
    return
  }

  const { data, error } = await supabase
    .from('households')
    .select('id')
    .eq('id', scope)
    .is('deleted_at', null)
    .maybeSingle()

  if (error) {
    console.error('admin-staff-manage scope lookup error:', error)
    throw json({ error: 'Failed to validate staff scope' }, 500)
  }

  if (!data) {
    throw json({ error: 'Invalid household scope' }, 400)
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  try {
    const { supabase, actor } = await requireAdmin(req, { requireSuperAdmin: true })
    const body = await parseBody(req)
    const action = typeof body.action === 'string' ? body.action.trim() : ''
    const userAgent = req.headers.get('user-agent')
    const ipAddress = pickClientIp(req)

    if (action === 'add') {
      const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : ''
      const initialScope = typeof body.initial_scope === 'string' ? body.initial_scope.trim() : ''

      if (!email || !initialScope) {
        return json({ error: 'email and initial_scope are required' }, 400)
      }

      await validateScope(supabase, initialScope)

      const { data: existingUser, error: lookupError } = await supabase
        .from('users')
        .select(STAFF_COLS)
        .eq('email', email)
        .is('deleted_at', null)
        .maybeSingle()

      if (lookupError) {
        console.error('admin-staff-manage add lookup error:', lookupError)
        return json({ error: 'Failed to find target user' }, 500)
      }

      if (!existingUser) {
        return json({ error: 'User not found for the provided email' }, 404)
      }

      if (existingUser.role === 'super_admin' || existingUser.staff_role === 'super_admin') {
        return json({ error: 'Target user is already a super admin' }, 400)
      }

      const previousState = {
        staff_role: existingUser.staff_role,
        staff_scope: existingUser.staff_scope,
        admin_permissions: existingUser.admin_permissions,
      }

      const { data: updatedUser, error: updateError } = await supabase
        .from('users')
        .update({
          staff_role: 'support_staff',
          staff_scope: initialScope,
          admin_permissions: existingUser.admin_permissions ?? {},
        })
        .eq('id', existingUser.id)
        .select(STAFF_COLS)
        .single()

      if (updateError) {
        console.error('admin-staff-manage add update error:', updateError)
        return json({ error: 'Failed to add support staff' }, 500)
      }

      await writeAuditLog(supabase, {
        adminUserId: actor.id,
        action: 'create',
        resourceType: 'user',
        resourceId: updatedUser.id,
        oldValues: previousState,
        newValues: {
          staff_role: updatedUser.staff_role,
          staff_scope: updatedUser.staff_scope,
          admin_permissions: updatedUser.admin_permissions,
        },
        description: `Granted support staff access to ${updatedUser.email}`,
        ipAddress,
        userAgent,
      })

      return json({
        staff: {
          ...updatedUser,
          display_name: updatedUser.display_name,
        },
      })
    }

    if (action === 'remove') {
      const staffUserId = typeof body.staff_user_id === 'string' ? body.staff_user_id.trim() : ''
      if (!staffUserId) {
        return json({ error: 'staff_user_id is required' }, 400)
      }

      const { data: existingUser, error: lookupError } = await supabase
        .from('users')
        .select(STAFF_COLS)
        .eq('id', staffUserId)
        .is('deleted_at', null)
        .maybeSingle()

      if (lookupError) {
        console.error('admin-staff-manage remove lookup error:', lookupError)
        return json({ error: 'Failed to find target user' }, 500)
      }

      if (!existingUser) {
        return json({ error: 'Target user not found' }, 404)
      }

      if (existingUser.role === 'super_admin' || existingUser.staff_role === 'super_admin') {
        return json({ error: 'Super admin access cannot be removed here' }, 400)
      }

      const previousState = {
        staff_role: existingUser.staff_role,
        staff_scope: existingUser.staff_scope,
        admin_permissions: existingUser.admin_permissions,
      }

      const { error: updateError } = await supabase
        .from('users')
        .update({
          staff_role: null,
          staff_scope: null,
          admin_permissions: {},
        })
        .eq('id', existingUser.id)

      if (updateError) {
        console.error('admin-staff-manage remove update error:', updateError)
        return json({ error: 'Failed to remove support staff access' }, 500)
      }

      await writeAuditLog(supabase, {
        adminUserId: actor.id,
        action: 'delete',
        resourceType: 'user',
        resourceId: existingUser.id,
        oldValues: previousState,
        newValues: {
          staff_role: null,
          staff_scope: null,
          admin_permissions: {},
        },
        description: `Removed support staff access from ${existingUser.email}`,
        ipAddress,
        userAgent,
      })

      return json({ success: true })
    }

    if (action === 'update_scope') {
      const staffUserId = typeof body.staff_user_id === 'string' ? body.staff_user_id.trim() : ''
      const newScope = typeof body.new_scope === 'string' ? body.new_scope.trim() : ''

      if (!staffUserId || !newScope) {
        return json({ error: 'staff_user_id and new_scope are required' }, 400)
      }

      await validateScope(supabase, newScope)

      const { data: existingUser, error: lookupError } = await supabase
        .from('users')
        .select(STAFF_COLS)
        .eq('id', staffUserId)
        .is('deleted_at', null)
        .maybeSingle()

      if (lookupError) {
        console.error('admin-staff-manage update scope lookup error:', lookupError)
        return json({ error: 'Failed to find target user' }, 500)
      }

      if (!existingUser) {
        return json({ error: 'Target user not found' }, 404)
      }

      if (existingUser.staff_role !== 'support_staff') {
        return json({ error: 'Target user is not support staff' }, 400)
      }

      const previousState = {
        staff_scope: existingUser.staff_scope,
      }

      const { data: updatedUser, error: updateError } = await supabase
        .from('users')
        .update({ staff_scope: newScope })
        .eq('id', existingUser.id)
        .select(STAFF_COLS)
        .single()

      if (updateError) {
        console.error('admin-staff-manage update scope error:', updateError)
        return json({ error: 'Failed to update staff scope' }, 500)
      }

      await writeAuditLog(supabase, {
        adminUserId: actor.id,
        action: 'update',
        resourceType: 'user',
        resourceId: updatedUser.id,
        oldValues: previousState,
        newValues: { staff_scope: updatedUser.staff_scope },
        description: `Updated support staff scope for ${updatedUser.email}`,
        ipAddress,
        userAgent,
      })

      return json({
        staff: {
          ...updatedUser,
          display_name: updatedUser.display_name,
        },
      })
    }

    return json({ error: 'Unsupported action' }, 400)
  } catch (error) {
    if (error instanceof Response) {
      return error
    }

    console.error('admin-staff-manage error:', error)
    return json({ error: 'Internal server error' }, 500)
  }
})