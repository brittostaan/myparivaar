import {
  ADMIN_PERMISSIONS,
  type AdminContext,
  json,
  parseBody,
  requireAdmin,
  requireAdminPermissions,
  writeAuditLog,
} from '../_shared/admin.ts'
import { corsHeaders } from '../_shared/cors.ts'

declare const Deno: {
  env: { get(name: string): string | undefined }
  serve(handler: (req: Request) => Response | Promise<Response>): void
}

type HouseholdRow = {
  id: string
  name: string
  plan: string
  suspended: boolean
  suspension_reason: string | null
  admin_notes: string | null
  created_at: string
  updated_at: string
}

type HouseholdMemberRow = {
  id: string
  display_name: string | null
  email: string | null
  role: string
  is_active: boolean
  created_at: string
}

function pickClientIp(req: Request): string | null {
  const forwarded = req.headers.get('x-forwarded-for')
  if (!forwarded) {
    return null
  }
  return forwarded.split(',')[0]?.trim() ?? null
}

function parseLimit(value: unknown, fallback = 100): number {
  const n = Number(value)
  if (!Number.isFinite(n)) {
    return fallback
  }
  return Math.max(1, Math.min(200, Math.trunc(n)))
}

function isGlobalScope(scope: string): boolean {
  return scope === 'global'
}

function canAccessHousehold(scope: string, householdId: string): boolean {
  return isGlobalScope(scope) || scope === householdId
}

async function getMemberCounts(
  supabase: AdminContext['supabase'],
  householdIds: string[],
): Promise<Map<string, { memberCount: number; activeMemberCount: number }>> {
  if (householdIds.length === 0) {
    return new Map()
  }

  const { data, error } = await supabase
    .from('users')
    .select('household_id, is_active')
    .in('household_id', householdIds)
    .is('deleted_at', null)

  if (error) {
    console.error('admin-households member counts error:', error)
    throw json({ error: 'Failed to load household member counts' }, 500)
  }

  const map = new Map<string, { memberCount: number; activeMemberCount: number }>()
  for (const id of householdIds) {
    map.set(id, { memberCount: 0, activeMemberCount: 0 })
  }

  for (const row of data ?? []) {
    const householdId = row.household_id as string | null
    if (!householdId || !map.has(householdId)) {
      continue
    }

    const current = map.get(householdId)!
    current.memberCount += 1
    if ((row.is_active as boolean | null) !== false) {
      current.activeMemberCount += 1
    }
  }

  return map
}

async function fetchHouseholdWithMembers(
  supabase: AdminContext['supabase'],
  householdId: string,
): Promise<{ household: HouseholdRow; members: HouseholdMemberRow[] }> {
  const { data: household, error: householdError } = await supabase
    .from('households')
    .select('id, name, plan, suspended, suspension_reason, admin_notes, created_at, updated_at')
    .eq('id', householdId)
    .is('deleted_at', null)
    .maybeSingle<HouseholdRow>()

  if (householdError) {
    console.error('admin-households household detail error:', householdError)
    throw json({ error: 'Failed to fetch household detail' }, 500)
  }

  if (!household) {
    throw json({ error: 'Household not found' }, 404)
  }

  const { data: members, error: membersError } = await supabase
    .from('users')
    .select('id, display_name, email, role, is_active, created_at')
    .eq('household_id', householdId)
    .is('deleted_at', null)
    .order('created_at', { ascending: true })

  if (membersError) {
    console.error('admin-households members detail error:', membersError)
    throw json({ error: 'Failed to fetch household members' }, 500)
  }

  return {
    household,
    members: (members ?? []) as HouseholdMemberRow[],
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
    const context = await requireAdmin(req)
    const { supabase, actor, scope } = context
    const body = await parseBody(req)
    const action = typeof body.action === 'string' ? body.action.trim() : ''
    const ipAddress = pickClientIp(req)
    const userAgent = req.headers.get('user-agent')

    if (action === 'list') {
      requireAdminPermissions(context, [ADMIN_PERMISSIONS.viewHouseholds])

      const queryText = typeof body.query === 'string' ? body.query.trim() : ''
      const suspendedOnly = body.suspended_only === true
      const limit = parseLimit(body.limit, 100)

      let query = supabase
        .from('households')
        .select('id, name, plan, suspended, created_at, updated_at')
        .is('deleted_at', null)
        .order('updated_at', { ascending: false })
        .limit(limit)

      if (!isGlobalScope(scope)) {
        query = query.eq('id', scope)
      }

      if (queryText) {
        query = query.ilike('name', `%${queryText}%`)
      }

      if (suspendedOnly) {
        query = query.eq('suspended', true)
      }

      const { data: households, error } = await query
      if (error) {
        console.error('admin-households list error:', error)
        return json({ error: 'Failed to fetch households' }, 500)
      }

      const rows = (households ?? []) as Array<{
        id: string
        name: string
        plan: string
        suspended: boolean
        created_at: string
        updated_at: string
      }>
      const householdIds = rows.map((row) => row.id as string)
      const counts = await getMemberCounts(supabase, householdIds)

      return json({
        households: rows.map((row) => {
          const householdId = row.id as string
          const count = counts.get(householdId) ?? { memberCount: 0, activeMemberCount: 0 }
          return {
            ...row,
            member_count: count.memberCount,
            active_member_count: count.activeMemberCount,
          }
        }),
      })
    }

    if (action === 'detail') {
      requireAdminPermissions(context, [ADMIN_PERMISSIONS.viewHouseholds])

      const householdId = typeof body.household_id === 'string' ? body.household_id.trim() : ''
      if (!householdId) {
        return json({ error: 'household_id is required' }, 400)
      }

      if (!canAccessHousehold(scope, householdId)) {
        return json({ error: 'Forbidden for this household scope' }, 403)
      }

      const { household, members } = await fetchHouseholdWithMembers(supabase, householdId)
      const activeMembers = members.filter((member) => member.is_active !== false)

      return json({
        household: {
          ...household,
          member_count: members.length,
          active_member_count: activeMembers.length,
          members,
        },
      })
    }

    if (action === 'suspend' || action === 'reactivate') {
      requireAdminPermissions(context, [ADMIN_PERMISSIONS.manageHouseholds])

      const householdId = typeof body.household_id === 'string' ? body.household_id.trim() : ''
      const reason = typeof body.reason === 'string' ? body.reason.trim() : ''

      if (!householdId) {
        return json({ error: 'household_id is required' }, 400)
      }
      if (!reason) {
        return json({ error: 'reason is required' }, 400)
      }

      if (!canAccessHousehold(scope, householdId)) {
        return json({ error: 'Forbidden for this household scope' }, 403)
      }

      const { household: existing } = await fetchHouseholdWithMembers(supabase, householdId)
      const shouldSuspend = action === 'suspend'

      if (existing.suspended === shouldSuspend) {
        return json({ error: shouldSuspend ? 'Household already suspended' : 'Household already active' }, 400)
      }

      const { error: updateError } = await supabase
        .from('households')
        .update({
          suspended: shouldSuspend,
          suspension_reason: shouldSuspend ? reason : null,
        })
        .eq('id', householdId)

      if (updateError) {
        console.error('admin-households suspend/reactivate update error:', updateError)
        return json({ error: 'Failed to update household status' }, 500)
      }

      await writeAuditLog(supabase, {
        adminUserId: actor.id,
        action: shouldSuspend ? 'suspend' : 'unsuspend',
        resourceType: 'household',
        resourceId: householdId,
        oldValues: {
          suspended: existing.suspended,
          suspension_reason: existing.suspension_reason,
        },
        newValues: {
          suspended: shouldSuspend,
          suspension_reason: shouldSuspend ? reason : null,
        },
        description: shouldSuspend
          ? `Suspended household ${existing.name}`
          : `Reactivated household ${existing.name}`,
        ipAddress,
        userAgent,
      })

      const { household, members } = await fetchHouseholdWithMembers(supabase, householdId)
      const activeMembers = members.filter((member) => member.is_active !== false)
      return json({
        household: {
          ...household,
          member_count: members.length,
          active_member_count: activeMembers.length,
          members,
        },
      })
    }

    if (action === 'update_notes') {
      requireAdminPermissions(context, [ADMIN_PERMISSIONS.manageHouseholds])

      const householdId = typeof body.household_id === 'string' ? body.household_id.trim() : ''
      const adminNotes = typeof body.admin_notes === 'string' ? body.admin_notes.trim() : ''

      if (!householdId) {
        return json({ error: 'household_id is required' }, 400)
      }

      if (!canAccessHousehold(scope, householdId)) {
        return json({ error: 'Forbidden for this household scope' }, 403)
      }

      const { household: existing } = await fetchHouseholdWithMembers(supabase, householdId)

      const { error: updateError } = await supabase
        .from('households')
        .update({
          admin_notes: adminNotes,
        })
        .eq('id', householdId)

      if (updateError) {
        console.error('admin-households update notes error:', updateError)
        return json({ error: 'Failed to update household notes' }, 500)
      }

      await writeAuditLog(supabase, {
        adminUserId: actor.id,
        action: 'update',
        resourceType: 'household',
        resourceId: householdId,
        oldValues: {
          admin_notes: existing.admin_notes,
        },
        newValues: {
          admin_notes: adminNotes,
        },
        description: `Updated admin notes for household ${existing.name}`,
        ipAddress,
        userAgent,
      })

      const { household, members } = await fetchHouseholdWithMembers(supabase, householdId)
      const activeMembers = members.filter((member) => member.is_active !== false)
      return json({
        household: {
          ...household,
          member_count: members.length,
          active_member_count: activeMembers.length,
          members,
        },
      })
    }

    return json({ error: 'Unsupported action' }, 400)
  } catch (error) {
    if (error instanceof Response) {
      return error
    }

    console.error('admin-households error:', error)
    return json({ error: 'Internal server error' }, 500)
  }
})
