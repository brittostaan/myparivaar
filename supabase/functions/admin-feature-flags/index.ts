import {
  ADMIN_PERMISSIONS,
  json,
  parseBody,
  requireAdmin,
  writeAuditLog,
} from '../_shared/admin.ts'
import { corsHeaders } from '../_shared/cors.ts'

function pickClientIp(req: Request): string | null {
  const forwarded = req.headers.get('x-forwarded-for')
  if (!forwarded) return null
  return forwarded.split(',')[0]?.trim() ?? null
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
    const { supabase, actor, isSuperAdmin } = context
    const body = await parseBody(req)
    const action = typeof body.action === 'string' ? body.action.trim() : ''

    // ── list_flags ─────────────────────────────────────────────────────────
    if (action === 'list_flags') {
      const householdId = typeof (body.householdId ?? body.household_id) === 'string' ? String(body.householdId ?? body.household_id).trim() : ''

      const { data: flags, error: flagsError } = await supabase
        .from('feature_flags')
        .select('*')
        .order('category')
        .order('name')

      if (flagsError) {
        console.error('feature_flags query error:', flagsError)
        return json({ error: 'Failed to fetch feature flags' }, 500)
      }

      // If householdId provided, enrich with household overrides
      let enrichedFlags = flags ?? []
      if (householdId) {
        const { data: overrides } = await supabase
          .from('household_feature_overrides')
          .select('*')
          .eq('household_id', householdId)

        if (overrides && overrides.length > 0) {
          const overrideMap = new Map(
            overrides.map((o: Record<string, unknown>) => [o.feature_flag_id, o]),
          )
          enrichedFlags = enrichedFlags.map((flag: Record<string, unknown>) => ({
            ...flag,
            household_override: overrideMap.get(flag.id) ?? null,
          }))
        }
      }

      return json({ flags: enrichedFlags })
    }

    // ── toggle_flag (super-admin only) ─────────────────────────────────────
    if (action === 'toggle_flag') {
      if (!isSuperAdmin) {
        return json({ error: 'Only super admins can toggle feature flags' }, 403)
      }

      const flagId = typeof (body.flagId ?? body.flag_id) === 'string' ? String(body.flagId ?? body.flag_id).trim() : ''
      if (!flagId) {
        return json({ error: 'flagId is required' }, 400)
      }

      // Get current state
      const { data: current, error: fetchError } = await supabase
        .from('feature_flags')
        .select('id, name, is_enabled')
        .eq('id', flagId)
        .maybeSingle()

      if (fetchError || !current) {
        return json({ error: 'Feature flag not found' }, 404)
      }

      // Toggle
      const newValue = !current.is_enabled
      const { data: updated, error: updateError } = await supabase
        .from('feature_flags')
        .update({ is_enabled: newValue })
        .eq('id', flagId)
        .select('*')
        .maybeSingle()

      if (updateError) {
        console.error('toggle_flag update error:', updateError)
        return json({ error: 'Failed to toggle feature flag' }, 500)
      }

      await writeAuditLog(supabase, {
        action: 'toggle_feature_flag',
        adminUserId: actor.id,
        resourceType: 'feature_flag',
        resourceId: flagId,
        details: { name: current.name, was: current.is_enabled, now: newValue },
        clientIp: pickClientIp(req),
      })

      return json({ flag: updated })
    }

    // ── set_household_override ─────────────────────────────────────────────
    if (action === 'set_household_override') {
      if (!isSuperAdmin) {
        return json({ error: 'Only super admins can set feature overrides' }, 403)
      }

      const householdId = typeof (body.householdId ?? body.household_id) === 'string' ? String(body.householdId ?? body.household_id).trim() : ''
      const flagId = typeof (body.flagId ?? body.flag_id) === 'string' ? String(body.flagId ?? body.flag_id).trim() : ''
      const isEnabled = (body.isEnabled ?? body.is_enabled) === true
      const reason = typeof body.reason === 'string' ? body.reason.trim() : null

      if (!householdId || !flagId) {
        return json({ error: 'householdId and flagId are required' }, 400)
      }

      // Upsert override
      const { data: override, error: upsertError } = await supabase
        .from('household_feature_overrides')
        .upsert(
          {
            household_id: householdId,
            feature_flag_id: flagId,
            is_enabled: isEnabled,
            reason,
            override_by_admin_id: actor.id,
          },
          { onConflict: 'household_id,feature_flag_id' },
        )
        .select('*')
        .maybeSingle()

      if (upsertError) {
        console.error('set_household_override error:', upsertError)
        return json({ error: 'Failed to set household override' }, 500)
      }

      await writeAuditLog(supabase, {
        action: 'set_feature_override',
        adminUserId: actor.id,
        resourceType: 'household',
        resourceId: householdId,
        details: { flag_id: flagId, is_enabled: isEnabled, reason },
        clientIp: pickClientIp(req),
      })

      return json({ override })
    }

    // ── remove_household_override ──────────────────────────────────────────
    if (action === 'remove_household_override') {
      if (!isSuperAdmin) {
        return json({ error: 'Only super admins can remove feature overrides' }, 403)
      }

      const overrideId = typeof (body.overrideId ?? body.override_id) === 'string' ? String(body.overrideId ?? body.override_id).trim() : ''
      if (!overrideId) {
        return json({ error: 'overrideId is required' }, 400)
      }

      const { error: deleteError } = await supabase
        .from('household_feature_overrides')
        .delete()
        .eq('id', overrideId)

      if (deleteError) {
        console.error('remove_household_override error:', deleteError)
        return json({ error: 'Failed to remove household override' }, 500)
      }

      await writeAuditLog(supabase, {
        action: 'remove_feature_override',
        adminUserId: actor.id,
        resourceType: 'feature_override',
        resourceId: overrideId,
        details: null,
        clientIp: pickClientIp(req),
      })

      return json({ success: true })
    }

    return json({ error: `Unknown action: ${action}` }, 400)
  } catch (thrown) {
    if (thrown instanceof Response) return thrown
    const msg = thrown instanceof Error ? thrown.message : 'Unexpected error'
    console.error('admin-feature-flags error:', msg)
    return json({ error: msg }, 500)
  }
})
