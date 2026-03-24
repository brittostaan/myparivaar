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

    if (action === 'create') {
      requireAdminPermissions(context, [ADMIN_PERMISSIONS.manageHouseholds])

      const name = typeof body.name === 'string' ? body.name.trim() : ''
      if (!name || name.length > 50) {
        return json({ error: 'name is required (1-50 characters)' }, 400)
      }

      const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : ''
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return json({ error: 'A valid email is required for the household admin' }, 400)
      }

      const password = typeof body.password === 'string' ? body.password : ''
      if (password.length < 6) {
        return json({ error: 'Password must be at least 6 characters' }, 400)
      }

      const displayName = typeof body.display_name === 'string' ? body.display_name.trim() : ''

      // 1. Create Supabase auth user
      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      })

      if (authError) {
        console.error('admin-households create auth user error:', authError)
        const msg = authError.message?.includes('already been registered')
          ? 'A user with this email already exists'
          : 'Failed to create auth user'
        return json({ error: msg }, 400)
      }

      const authUserId = authData.user.id

      // 2. Create household
      const { data: household, error: insertError } = await supabase
        .from('households')
        .insert({ name, admin_firebase_uid: authUserId })
        .select('id, name, plan, suspended, created_at, updated_at')
        .single()

      if (insertError) {
        console.error('admin-households create household error:', insertError)
        // Rollback: delete auth user
        await supabase.auth.admin.deleteUser(authUserId)
        return json({ error: 'Failed to create household' }, 500)
      }

      // 3. Create user record linked to the household
      const { error: userError } = await supabase
        .from('users')
        .insert({
          firebase_uid: authUserId,
          email,
          household_id: household.id,
          role: 'admin',
          ...(displayName ? { display_name: displayName } : {}),
        })

      if (userError) {
        console.error('admin-households create user record error:', userError)
        // Rollback: delete household and auth user
        await supabase.from('households').delete().eq('id', household.id)
        await supabase.auth.admin.deleteUser(authUserId)
        return json({ error: 'Failed to create user record' }, 500)
      }

      await writeAuditLog(supabase, {
        adminUserId: actor.id,
        action: 'create',
        resourceType: 'household',
        resourceId: household.id,
        oldValues: null,
        newValues: { name, admin_email: email },
        description: `Created household "${name}" with admin ${email}`,
        ipAddress,
        userAgent,
      })

      return json({ household }, 201)
    }

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

    if (action === 'get_ai_settings') {
      requireAdminPermissions(context, [ADMIN_PERMISSIONS.viewHouseholds])

      const householdId = typeof body.household_id === 'string' ? body.household_id.trim() : ''
      if (!householdId) {
        return json({ error: 'household_id is required' }, 400)
      }
      if (!canAccessHousehold(scope, householdId)) {
        return json({ error: 'Forbidden for this household scope' }, 403)
      }

      // Fetch AI settings (or return defaults if none exist)
      const { data: settings, error: fetchError } = await supabase
        .from('household_ai_settings')
        .select('*')
        .eq('household_id', householdId)
        .maybeSingle()

      if (fetchError) {
        console.error('admin-households get_ai_settings error:', fetchError)
        return json({ error: 'Failed to fetch AI settings' }, 500)
      }

      // Fetch current usage for this month
      const currentMonth = new Date().toISOString().slice(0, 7) // YYYY-MM
      const { data: usage } = await supabase
        .from('ai_usage')
        .select('chat_count, summary_generated_at, budget_analysis_count, anomaly_count, simulator_count')
        .eq('household_id', householdId)
        .eq('month', currentMonth)
        .maybeSingle()

      return json({
        ai_settings: settings ?? {
          household_id: householdId,
          ai_enabled: true,
          chat_queries_limit: 5,
          weekly_summaries_limit: 1,
          budget_analysis_limit: 10,
          anomaly_detection_limit: 5,
          simulator_limit: 5,
        },
        ai_usage: usage ?? {
          chat_count: 0,
          summary_generated_at: null,
          budget_analysis_count: 0,
          anomaly_count: 0,
          simulator_count: 0,
        },
      })
    }

    if (action === 'update_ai_settings') {
      requireAdminPermissions(context, [ADMIN_PERMISSIONS.manageHouseholds])

      const householdId = typeof body.household_id === 'string' ? body.household_id.trim() : ''
      if (!householdId) {
        return json({ error: 'household_id is required' }, 400)
      }
      if (!canAccessHousehold(scope, householdId)) {
        return json({ error: 'Forbidden for this household scope' }, 403)
      }

      const updates: Record<string, unknown> = { updated_at: new Date().toISOString() }
      if (typeof body.ai_enabled === 'boolean') updates.ai_enabled = body.ai_enabled
      if (typeof body.chat_queries_limit === 'number') updates.chat_queries_limit = Math.max(0, Math.trunc(body.chat_queries_limit))
      if (typeof body.weekly_summaries_limit === 'number') updates.weekly_summaries_limit = Math.max(0, Math.trunc(body.weekly_summaries_limit))
      if (typeof body.budget_analysis_limit === 'number') updates.budget_analysis_limit = Math.max(0, Math.trunc(body.budget_analysis_limit))
      if (typeof body.anomaly_detection_limit === 'number') updates.anomaly_detection_limit = Math.max(0, Math.trunc(body.anomaly_detection_limit))
      if (typeof body.simulator_limit === 'number') updates.simulator_limit = Math.max(0, Math.trunc(body.simulator_limit))

      // Upsert: insert if not exists, update if exists
      const { data: settings, error: upsertError } = await supabase
        .from('household_ai_settings')
        .upsert(
          { household_id: householdId, ...updates },
          { onConflict: 'household_id' },
        )
        .select()
        .single()

      if (upsertError) {
        console.error('admin-households update_ai_settings error:', upsertError)
        return json({ error: 'Failed to update AI settings' }, 500)
      }

      // Fetch household name for audit log
      const { data: hData } = await supabase
        .from('households')
        .select('name')
        .eq('id', householdId)
        .single()

      await writeAuditLog(supabase, {
        adminUserId: actor.id,
        action: 'update',
        resourceType: 'household',
        resourceId: householdId,
        oldValues: {},
        newValues: updates,
        description: `Updated AI settings for household ${hData?.name ?? householdId}`,
        ipAddress,
        userAgent,
      })

      return json({ ai_settings: settings })
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
