import {
  ADMIN_PERMISSIONS,
  json,
  parseBody,
  requireAdmin,
  writeAuditLog,
} from '../_shared/admin.ts'
import { corsHeaders } from '../_shared/cors.ts'

function parseLimit(value: unknown, fallback = 100): number {
  const n = Number(value)
  if (!Number.isFinite(n)) return fallback
  return Math.max(1, Math.min(500, Math.trunc(n)))
}

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
      requiredPermissions: [ADMIN_PERMISSIONS.viewHouseholds],
    })
    const { supabase, actor, isSuperAdmin } = context
    const body = await parseBody(req)
    const action = typeof body.action === 'string' ? body.action.trim() : ''

    // ── list_subscriptions ───────────────────────────────────────────────────
    if (action === 'list_subscriptions') {
      const limit = parseLimit(body.limit, 100)
      const statusFilter = typeof body.status === 'string' ? body.status.trim() : ''

      let query = supabase
        .from('subscriptions')
        .select('id, household_id, status, billing_cycle, amount_paid, currency, started_at, expires_at, cancelled_at, created_at, plan_id')
        .is('deleted_at', null)
        .order('created_at', { ascending: false })
        .limit(limit)

      if (statusFilter) {
        query = query.eq('status', statusFilter)
      }

      const { data, error } = await query

      if (error) {
        console.error('admin-subscriptions list error:', error)
        return json({ error: 'Failed to list subscriptions' }, 500)
      }

      const rows = data ?? []

      // Collect unique plan_ids and household_ids for batch lookup
      const planIds = [...new Set(rows.map((r: Record<string, unknown>) => r.plan_id as string).filter(Boolean))]
      const householdIds = [...new Set(rows.map((r: Record<string, unknown>) => r.household_id as string).filter(Boolean))]

      // Batch fetch plans and households
      const [plansRes, householdsRes] = await Promise.all([
        planIds.length > 0
          ? supabase.from('plans').select('id, name, display_name, price_monthly').in('id', planIds)
          : Promise.resolve({ data: [], error: null }),
        householdIds.length > 0
          ? supabase.from('households').select('id, name').in('id', householdIds)
          : Promise.resolve({ data: [], error: null }),
      ])

      const planMap = new Map((plansRes.data ?? []).map((p: Record<string, unknown>) => [p.id, p]))
      const hhMap = new Map((householdsRes.data ?? []).map((h: Record<string, unknown>) => [h.id, h]))

      const result = rows.map((s: Record<string, unknown>) => {
        const plan = planMap.get(s.plan_id) as Record<string, unknown> | undefined
        const hh = hhMap.get(s.household_id) as Record<string, unknown> | undefined
        return {
          id: s.id,
          household_id: s.household_id,
          household_name: hh?.name ?? null,
          plan_id: s.plan_id,
          plan_name: plan?.name ?? null,
          plan_display_name: plan?.display_name ?? null,
          status: s.status,
          billing_cycle: s.billing_cycle,
          amount_paid: s.amount_paid,
          currency: s.currency,
          started_at: s.started_at,
          expires_at: s.expires_at,
          cancelled_at: s.cancelled_at,
          created_at: s.created_at,
        }
      })

      return json({ subscriptions: result, total: result.length })
    }

    // ── change_plan ──────────────────────────────────────────────────────────
    if (action === 'change_plan') {
      if (!isSuperAdmin) {
        return json({ error: 'Only super admins can change plans' }, 403)
      }

      const householdId = typeof body.household_id === 'string' ? body.household_id.trim() : ''
      const planName = typeof body.plan_name === 'string' ? body.plan_name.trim() : ''
      const reason = typeof body.reason === 'string' ? body.reason.trim() : null

      if (!householdId || !planName) {
        return json({ error: 'household_id and plan_name are required' }, 400)
      }

      // Look up household
      const { data: household, error: hhError } = await supabase
        .from('households')
        .select('id, name, plan')
        .eq('id', householdId)
        .is('deleted_at', null)
        .maybeSingle()

      if (hhError) {
        console.error('admin-subscriptions change_plan household error:', hhError)
        return json({ error: 'Failed to look up household' }, 500)
      }
      if (!household) {
        return json({ error: 'Household not found' }, 404)
      }

      // Look up target plan
      const { data: plan, error: planError } = await supabase
        .from('plans')
        .select('id, name, display_name, price_monthly')
        .eq('name', planName)
        .eq('is_active', true)
        .maybeSingle()

      if (planError) {
        console.error('admin-subscriptions change_plan plan error:', planError)
        return json({ error: 'Failed to look up plan' }, 500)
      }
      if (!plan) {
        return json({ error: `Plan '${planName}' not found or inactive` }, 404)
      }

      const ipAddress = pickClientIp(req)
      const userAgent = req.headers.get('user-agent')
      const previousPlan = household.plan

      // Cancel existing active subscription for this household (if any)
      await supabase
        .from('subscriptions')
        .update({ status: 'cancelled', cancelled_at: new Date().toISOString() })
        .eq('household_id', householdId)
        .eq('status', 'active')

      // Create new subscription
      const { data: newSub, error: createError } = await supabase
        .from('subscriptions')
        .insert({
          household_id: householdId,
          plan_id: plan.id,
          status: 'active',
          billing_cycle: 'monthly',
          amount_paid: plan.price_monthly,
          currency: 'INR',
          started_at: new Date().toISOString(),
        })
        .select(`
          id, household_id, status, billing_cycle, amount_paid, currency,
          started_at, expires_at, cancelled_at, created_at, plan_id
        `)
        .single()

      if (createError) {
        console.error('admin-subscriptions create sub error:', createError)
        return json({ error: 'Failed to create subscription' }, 500)
      }

      // Update household.plan to match
      await supabase
        .from('households')
        .update({ plan: planName })
        .eq('id', householdId)

      await writeAuditLog(supabase, {
        adminUserId: actor.id,
        action: 'update',
        resourceType: 'subscription',
        resourceId: newSub.id,
        oldValues: { plan: previousPlan },
        newValues: { plan: planName },
        description: `Changed plan for ${household.name} from '${previousPlan}' to '${planName}'${reason ? `: ${reason}` : ''}`,
        ipAddress,
        userAgent,
      })

      return json({
        subscription: {
          ...newSub,
          household_name: household.name,
          plan_name: plan.name,
          plan_display_name: plan.display_name,
        },
      })
    }

    // ── cancel_subscription ──────────────────────────────────────────────────
    if (action === 'cancel_subscription') {
      if (!isSuperAdmin) {
        return json({ error: 'Only super admins can cancel subscriptions' }, 403)
      }

      const subscriptionId = typeof body.subscription_id === 'string'
        ? body.subscription_id.trim()
        : ''
      const reason = typeof body.reason === 'string' ? body.reason.trim() : null

      if (!subscriptionId) {
        return json({ error: 'subscription_id is required' }, 400)
      }

      const { data: sub, error: subError } = await supabase
        .from('subscriptions')
        .select('id, household_id, status, plan_id')
        .eq('id', subscriptionId)
        .is('deleted_at', null)
        .maybeSingle()

      if (subError) {
        console.error('admin-subscriptions cancel error:', subError)
        return json({ error: 'Failed to look up subscription' }, 500)
      }
      if (!sub) {
        return json({ error: 'Subscription not found' }, 404)
      }
      if (sub.status === 'cancelled') {
        return json({ error: 'Subscription is already cancelled' }, 400)
      }

      // Fetch plan and household names separately
      const [planRes, hhRes] = await Promise.all([
        supabase.from('plans').select('name, display_name').eq('id', sub.plan_id).maybeSingle(),
        supabase.from('households').select('name').eq('id', sub.household_id).maybeSingle(),
      ])

      const ipAddress = pickClientIp(req)
      const userAgent = req.headers.get('user-agent')

      const { data: updated, error: updateError } = await supabase
        .from('subscriptions')
        .update({ status: 'cancelled', cancelled_at: new Date().toISOString() })
        .eq('id', subscriptionId)
        .select('id, status, cancelled_at')
        .single()

      if (updateError) {
        console.error('admin-subscriptions cancel update error:', updateError)
        return json({ error: 'Failed to cancel subscription' }, 500)
      }

      const householdName = hhRes.data?.name ?? 'Unknown'
      const planName = planRes.data?.name ?? 'unknown'

      await writeAuditLog(supabase, {
        adminUserId: actor.id,
        action: 'update',
        resourceType: 'subscription',
        resourceId: subscriptionId,
        oldValues: { status: sub.status },
        newValues: { status: 'cancelled' },
        description: `Cancelled ${planName} subscription for ${householdName}${reason ? `: ${reason}` : ''}`,
        ipAddress,
        userAgent,
      })

      return json({ subscription: updated })
    }

    // ── list_plans ───────────────────────────────────────────────────────────
    if (action === 'list_plans') {
      const { data, error } = await supabase
        .from('plans')
        .select(`
          id, name, display_name, description,
          price_monthly, price_yearly, currency,
          max_family_members, ai_weekly_summaries, ai_chat_queries,
          csv_import_enabled, email_ingestion_enabled, voice_features_enabled,
          is_active, created_at, updated_at
        `)
        .order('price_monthly', { ascending: true })

      if (error) {
        console.error('admin-subscriptions list_plans error:', error)
        return json({ error: 'Failed to list plans' }, 500)
      }

      return json({ plans: data ?? [] })
    }

    // ── update_plan ──────────────────────────────────────────────────────────
    if (action === 'update_plan') {
      if (!isSuperAdmin) {
        return json({ error: 'Only super admins can update plans' }, 403)
      }

      const planId = typeof body.plan_id === 'string' ? body.plan_id.trim() : ''
      if (!planId) {
        return json({ error: 'plan_id is required' }, 400)
      }

      const { data: existing, error: fetchError } = await supabase
        .from('plans')
        .select('id, name, display_name, description, price_monthly, price_yearly, max_family_members, ai_weekly_summaries, ai_chat_queries')
        .eq('id', planId)
        .maybeSingle()

      if (fetchError) {
        console.error('admin-subscriptions update_plan fetch error:', fetchError)
        return json({ error: 'Failed to look up plan' }, 500)
      }
      if (!existing) {
        return json({ error: 'Plan not found' }, 404)
      }

      type UpdatePayload = Record<string, unknown>
      const updates: UpdatePayload = {}
      if (typeof body.display_name === 'string') updates.display_name = body.display_name.trim()
      if (typeof body.description === 'string') updates.description = body.description.trim()
      if (typeof body.price_monthly === 'number') updates.price_monthly = body.price_monthly
      if (typeof body.price_yearly === 'number') updates.price_yearly = body.price_yearly
      if (typeof body.max_family_members === 'number') updates.max_family_members = body.max_family_members
      if (typeof body.ai_weekly_summaries === 'number') updates.ai_weekly_summaries = body.ai_weekly_summaries
      if (typeof body.ai_chat_queries === 'number') updates.ai_chat_queries = body.ai_chat_queries

      if (Object.keys(updates).length === 0) {
        return json({ error: 'No valid fields to update' }, 400)
      }

      const { data: updatedPlan, error: updateError } = await supabase
        .from('plans')
        .update(updates)
        .eq('id', planId)
        .select()
        .single()

      if (updateError) {
        console.error('admin-subscriptions update_plan error:', updateError)
        return json({ error: 'Failed to update plan' }, 500)
      }

      const ipAddress = pickClientIp(req)
      const userAgent = req.headers.get('user-agent')

      await writeAuditLog(supabase, {
        adminUserId: actor.id,
        action: 'update',
        resourceType: 'plan',
        resourceId: planId,
        oldValues: existing as Record<string, unknown>,
        newValues: updates,
        description: `Updated plan '${existing.name}' limits`,
        ipAddress,
        userAgent,
      })

      return json({ plan: updatedPlan })
    }

    return json({ error: 'Unsupported action' }, 400)
  } catch (error) {
    if (error instanceof Response) return error

    console.error('admin-subscriptions error:', error)
    return json({ error: 'Internal server error' }, 500)
  }
})
