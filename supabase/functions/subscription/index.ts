import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

/**
 * User-facing subscription & payment management.
 *
 * Actions:
 *   get_plans           – list available subscription plans
 *   get_subscription    – get current household subscription
 *   get_active_gateways – list active payment gateways
 *   create_subscription – subscribe household to a plan
 *   cancel_subscription – cancel a subscription
 *   get_payment_history – list payment history for household
 */
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  // Verify JWT
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader.startsWith('Bearer ')) {
    return json({ error: 'Missing Authorization header' }, 401)
  }
  const token = authHeader.slice(7).trim()

  const anonClient = createClient(supabaseUrl, supabaseAnonKey, {
    auth: { persistSession: false },
  })

  const { data: { user: authUser }, error: authError } = await anonClient.auth.getUser(token)
  if (authError || !authUser) {
    return json({ error: 'Invalid token' }, 401)
  }

  // Service role client for DB operations
  const supabase = createClient(supabaseUrl, supabaseServiceKey, {
    db: { schema: 'app' },
  })

  // Look up app user
  const { data: appUser, error: userErr } = await supabase
    .from('users')
    .select('id, household_id, role')
    .eq('firebase_uid', authUser.id)
    .is('deleted_at', null)
    .maybeSingle()

  if (userErr || !appUser) {
    return json({ error: 'User not found' }, 404)
  }

  let body: Record<string, any> = {}
  try {
    body = await req.json()
  } catch { /* empty body is fine for some actions */ }

  const action = String(body.action ?? '')

  try {
    // ── get_plans ──────────────────────────────────────────────────────────
    if (action === 'get_plans') {
      const { data: plans, error } = await supabase
        .from('plans')
        .select('id, name, price_monthly, price_yearly, features, is_active, max_members, max_accounts, ai_queries_per_month')
        .eq('is_active', true)
        .order('price_monthly')

      if (error) {
        console.error('get_plans error:', error)
        return json({ error: 'Failed to fetch plans' }, 500)
      }

      return json({ plans: plans ?? [] })
    }

    // ── get_active_gateways ────────────────────────────────────────────────
    if (action === 'get_active_gateways') {
      const { data: gateways, error } = await supabase
        .from('payment_gateway_configs')
        .select('gateway, display_name, is_test_mode')
        .eq('is_active', true)
        .order('gateway')

      if (error) {
        console.error('get_active_gateways error:', error)
        return json({ error: 'Failed to fetch gateways' }, 500)
      }

      return json({ gateways: gateways ?? [] })
    }

    // ── get_subscription ───────────────────────────────────────────────────
    if (action === 'get_subscription') {
      if (!appUser.household_id) {
        return json({ subscription: null, message: 'No household linked' })
      }

      const { data: sub, error } = await supabase
        .from('household_subscriptions')
        .select(`
          id, household_id, plan_id, status, gateway, gateway_subscription_id,
          current_period_start, current_period_end, cancelled_at, created_at, updated_at
        `)
        .eq('household_id', appUser.household_id)
        .in('status', ['active', 'trialing', 'past_due'])
        .order('created_at', { ascending: false })
        .maybeSingle()

      if (error) {
        console.error('get_subscription error:', error)
        return json({ error: 'Failed to fetch subscription' }, 500)
      }

      // Also fetch plan details if subscription exists
      let plan = null
      if (sub?.plan_id) {
        const { data: planData } = await supabase
          .from('plans')
          .select('id, name, price_monthly, price_yearly, features, max_members, max_accounts, ai_queries_per_month')
          .eq('id', sub.plan_id)
          .maybeSingle()
        plan = planData
      }

      return json({ subscription: sub, plan })
    }

    // ── create_subscription ────────────────────────────────────────────────
    if (action === 'create_subscription') {
      if (!appUser.household_id) {
        return json({ error: 'No household linked. Create or join a household first.' }, 400)
      }

      const planId = String(body.plan_id ?? '').trim()
      const gateway = String(body.gateway ?? '').trim().toLowerCase()

      if (!planId) return json({ error: 'plan_id is required' }, 400)
      if (!['stripe', 'razorpay', 'phonepe'].includes(gateway)) {
        return json({ error: 'Invalid gateway' }, 400)
      }

      // Verify plan exists
      const { data: plan } = await supabase
        .from('plans')
        .select('id, name, price_monthly')
        .eq('id', planId)
        .eq('is_active', true)
        .maybeSingle()

      if (!plan) return json({ error: 'Plan not found or inactive' }, 404)

      // Verify gateway is active
      const { data: gwConfig } = await supabase
        .from('payment_gateway_configs')
        .select('gateway, is_active')
        .eq('gateway', gateway)
        .eq('is_active', true)
        .maybeSingle()

      if (!gwConfig) return json({ error: `Payment gateway ${gateway} is not available` }, 400)

      // Check for existing active subscription
      const { data: existingSub } = await supabase
        .from('household_subscriptions')
        .select('id, status')
        .eq('household_id', appUser.household_id)
        .in('status', ['active', 'trialing'])
        .maybeSingle()

      if (existingSub) {
        return json({ error: 'Household already has an active subscription. Cancel it first to change plans.' }, 400)
      }

      const now = new Date()
      const periodEnd = new Date(now)
      periodEnd.setMonth(periodEnd.getMonth() + 1)

      // Create subscription record
      const { data: newSub, error: subErr } = await supabase
        .from('household_subscriptions')
        .insert({
          household_id: appUser.household_id,
          plan_id: planId,
          status: 'active',
          gateway,
          current_period_start: now.toISOString(),
          current_period_end: periodEnd.toISOString(),
          created_by: appUser.id,
        })
        .select('id, household_id, plan_id, status, gateway, current_period_start, current_period_end, created_at')
        .single()

      if (subErr) {
        console.error('create_subscription error:', subErr)
        return json({ error: 'Failed to create subscription' }, 500)
      }

      // Record payment
      const { error: payErr } = await supabase
        .from('payment_history')
        .insert({
          household_id: appUser.household_id,
          subscription_id: newSub.id,
          gateway,
          amount_cents: plan.price_monthly * 100,
          currency: 'INR',
          status: 'succeeded',
          description: `Subscription to ${plan.name}`,
        })

      if (payErr) console.error('payment_history insert error:', payErr)

      return json({ subscription: newSub, plan }, 201)
    }

    // ── cancel_subscription ────────────────────────────────────────────────
    if (action === 'cancel_subscription') {
      if (!appUser.household_id) {
        return json({ error: 'No household linked' }, 400)
      }

      const subscriptionId = String(body.subscription_id ?? '').trim()
      if (!subscriptionId) return json({ error: 'subscription_id is required' }, 400)

      const { data: sub } = await supabase
        .from('household_subscriptions')
        .select('id, status, household_id')
        .eq('id', subscriptionId)
        .eq('household_id', appUser.household_id)
        .maybeSingle()

      if (!sub) return json({ error: 'Subscription not found' }, 404)
      if (sub.status === 'cancelled') return json({ error: 'Already cancelled' }, 400)

      const { error: cancelErr } = await supabase
        .from('household_subscriptions')
        .update({
          status: 'cancelled',
          cancelled_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('id', subscriptionId)

      if (cancelErr) {
        console.error('cancel_subscription error:', cancelErr)
        return json({ error: 'Failed to cancel subscription' }, 500)
      }

      return json({ cancelled: true, subscription_id: subscriptionId })
    }

    // ── get_payment_history ────────────────────────────────────────────────
    if (action === 'get_payment_history') {
      if (!appUser.household_id) {
        return json({ payments: [] })
      }

      const { data: payments, error } = await supabase
        .from('payment_history')
        .select('id, gateway, amount_cents, currency, status, description, receipt_url, created_at')
        .eq('household_id', appUser.household_id)
        .order('created_at', { ascending: false })
        .limit(50)

      if (error) {
        console.error('get_payment_history error:', error)
        return json({ error: 'Failed to fetch payment history' }, 500)
      }

      return json({ payments: payments ?? [] })
    }

    return json({ error: `Unknown action: ${action}` }, 400)
  } catch (err: any) {
    console.error('subscription error:', err)
    return json({ error: 'Internal server error' }, 500)
  }
})
