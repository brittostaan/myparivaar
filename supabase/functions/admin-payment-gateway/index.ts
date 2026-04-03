import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import {
  json,
  parseBody,
  requireAdmin,
  writeAuditLog,
} from '../_shared/admin.ts'
import { corsHeaders } from '../_shared/cors.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

/**
 * Admin-only payment gateway configuration management.
 *
 * Actions:
 *   list_gateways   – returns configured gateways with masked secrets
 *   upsert_gateway  – create or update gateway credentials
 *   delete_gateway   – remove a gateway configuration
 *   toggle_gateway  – activate/deactivate a gateway
 *   test_gateway    – basic validation of credentials
 */
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    const ctx = await requireAdmin(req, { requireSuperAdmin: true })
    const body = await parseBody(req)
    const action = String(body.action ?? '')

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: 'app' },
    })

    // ── list_gateways ────────────────────────────────────────────────────────
    if (action === 'list_gateways') {
      const { data: rows, error } = await supabase
        .from('payment_gateway_configs')
        .select('id, gateway, display_name, api_key, is_active, is_test_mode, config_json, created_at, updated_at')
        .order('gateway')

      if (error) {
        console.error('list_gateways error:', error)
        return json({ error: 'Failed to fetch gateway configs' }, 500)
      }

      const gateways = (rows ?? []).map((row: any) => ({
        ...row,
        api_key_masked: row.api_key
          ? '****' + row.api_key.slice(-8)
          : null,
        has_secret: true,
      }))

      return json({ gateways })
    }

    // ── upsert_gateway ───────────────────────────────────────────────────────
    if (action === 'upsert_gateway') {
      const gateway = String(body.gateway ?? '').toLowerCase()
      if (!['stripe', 'razorpay', 'phonepe'].includes(gateway)) {
        return json({ error: 'Gateway must be "stripe", "razorpay", or "phonepe"' }, 400)
      }

      const apiKey = String(body.api_key ?? '').trim()
      const apiSecret = String(body.api_secret ?? '').trim()

      if (!apiKey || apiKey.length < 8) {
        return json({ error: 'api_key is required (min 8 chars)' }, 400)
      }
      if (!apiSecret || apiSecret.length < 8) {
        return json({ error: 'api_secret is required (min 8 chars)' }, 400)
      }

      const displayNames: Record<string, string> = {
        stripe: 'Stripe',
        razorpay: 'Razorpay',
        phonepe: 'PhonePe',
      }

      const webhookSecret = body.webhook_secret
        ? String(body.webhook_secret).trim()
        : null

      const { data: existing } = await supabase
        .from('payment_gateway_configs')
        .select('id, api_key, is_active')
        .eq('gateway', gateway)
        .maybeSingle()

      const isActive = body.is_active !== false
      const isTestMode = body.is_test_mode !== false

      const upsertPayload: Record<string, unknown> = {
        gateway,
        display_name: displayNames[gateway] ?? gateway,
        api_key: apiKey,
        api_secret: apiSecret,
        is_active: isActive,
        is_test_mode: isTestMode,
        updated_at: new Date().toISOString(),
        updated_by: ctx.actor.id,
      }
      if (webhookSecret) {
        upsertPayload.webhook_secret = webhookSecret
      }
      if (body.config_json) {
        upsertPayload.config_json = body.config_json
      }

      const { data: result, error: upsertError } = await supabase
        .from('payment_gateway_configs')
        .upsert(upsertPayload, { onConflict: 'gateway' })
        .select('id, gateway, display_name, api_key, is_active, is_test_mode, config_json, created_at, updated_at')
        .single()

      if (upsertError) {
        console.error('upsert_gateway error:', upsertError)
        return json({ error: 'Failed to save gateway config' }, 500)
      }

      await writeAuditLog(supabase, {
        adminUserId: ctx.actor.id,
        action: existing ? 'update_payment_gateway' : 'create_payment_gateway',
        resourceType: 'payment_gateway_config',
        resourceId: result.id,
        oldValues: existing
          ? { api_key: '****' + existing.api_key.slice(-8), is_active: existing.is_active }
          : null,
        newValues: {
          gateway,
          api_key: '****' + apiKey.slice(-8),
          is_active: isActive,
          is_test_mode: isTestMode,
        },
        description: `${existing ? 'Updated' : 'Created'} payment gateway config for ${displayNames[gateway]}`,
      })

      return json({
        gateway_config: {
          ...result,
          api_key_masked: '****' + result.api_key.slice(-8),
          has_secret: true,
        },
        created: !existing,
      })
    }

    // ── delete_gateway ───────────────────────────────────────────────────────
    if (action === 'delete_gateway') {
      const gateway = String(body.gateway ?? '').toLowerCase()
      if (!['stripe', 'razorpay', 'phonepe'].includes(gateway)) {
        return json({ error: 'Gateway must be "stripe", "razorpay", or "phonepe"' }, 400)
      }

      const { data: existing } = await supabase
        .from('payment_gateway_configs')
        .select('id, gateway, api_key, display_name')
        .eq('gateway', gateway)
        .maybeSingle()

      if (!existing) {
        return json({ error: `No config found for gateway: ${gateway}` }, 404)
      }

      const { error: deleteError } = await supabase
        .from('payment_gateway_configs')
        .delete()
        .eq('gateway', gateway)

      if (deleteError) {
        console.error('delete_gateway error:', deleteError)
        return json({ error: 'Failed to delete gateway config' }, 500)
      }

      await writeAuditLog(supabase, {
        adminUserId: ctx.actor.id,
        action: 'delete_payment_gateway',
        resourceType: 'payment_gateway_config',
        resourceId: existing.id,
        oldValues: {
          gateway: existing.gateway,
          api_key: '****' + existing.api_key.slice(-8),
        },
        newValues: null,
        description: `Deleted payment gateway config for ${existing.display_name}`,
      })

      return json({ deleted: true, gateway })
    }

    // ── toggle_gateway ───────────────────────────────────────────────────────
    if (action === 'toggle_gateway') {
      const gateway = String(body.gateway ?? '').toLowerCase()
      const isActive = body.is_active === true

      const { data: existing } = await supabase
        .from('payment_gateway_configs')
        .select('id, gateway, is_active, display_name')
        .eq('gateway', gateway)
        .maybeSingle()

      if (!existing) {
        return json({ error: `No config found for gateway: ${gateway}` }, 404)
      }

      const { error: updateError } = await supabase
        .from('payment_gateway_configs')
        .update({ is_active: isActive, updated_at: new Date().toISOString(), updated_by: ctx.actor.id })
        .eq('gateway', gateway)

      if (updateError) {
        console.error('toggle_gateway error:', updateError)
        return json({ error: 'Failed to toggle gateway' }, 500)
      }

      await writeAuditLog(supabase, {
        adminUserId: ctx.actor.id,
        action: 'toggle_payment_gateway',
        resourceType: 'payment_gateway_config',
        resourceId: existing.id,
        oldValues: { is_active: existing.is_active },
        newValues: { is_active: isActive },
        description: `${isActive ? 'Activated' : 'Deactivated'} ${existing.display_name}`,
      })

      return json({ gateway, is_active: isActive })
    }

    // ── test_gateway ─────────────────────────────────────────────────────────
    if (action === 'test_gateway') {
      const gateway = String(body.gateway ?? '').toLowerCase()
      if (!['stripe', 'razorpay', 'phonepe'].includes(gateway)) {
        return json({ error: 'Gateway must be "stripe", "razorpay", or "phonepe"' }, 400)
      }

      const { data: config } = await supabase
        .from('payment_gateway_configs')
        .select('api_key, api_secret, is_active, is_test_mode')
        .eq('gateway', gateway)
        .maybeSingle()

      if (!config) {
        return json({
          gateway,
          status: 'not_configured',
          message: `No credentials found for ${gateway}`,
        })
      }

      // Basic validation — check key format
      let valid = false
      let message = ''

      if (gateway === 'stripe') {
        valid = config.api_key.startsWith('sk_') || config.api_key.startsWith('pk_')
        message = valid
          ? 'Stripe API key format looks valid'
          : 'Stripe key should start with sk_ or pk_'
      } else if (gateway === 'razorpay') {
        valid = config.api_key.startsWith('rzp_')
        message = valid
          ? 'Razorpay API key format looks valid'
          : 'Razorpay key should start with rzp_'
      } else if (gateway === 'phonepe') {
        valid = config.api_key.length >= 10
        message = valid
          ? 'PhonePe Merchant ID format looks valid'
          : 'PhonePe Merchant ID seems too short'
      }

      return json({
        gateway,
        status: valid ? 'valid' : 'invalid_format',
        is_active: config.is_active,
        is_test_mode: config.is_test_mode,
        message,
      })
    }

    return json({ error: `Unknown action: ${action}` }, 400)
  } catch (err: any) {
    if (err.status) {
      return json({ error: err.message || 'Forbidden' }, err.status)
    }
    console.error('admin-payment-gateway error:', err)
    return json({ error: 'Internal server error' }, 500)
  }
})
