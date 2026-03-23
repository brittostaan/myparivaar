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
 * Admin-only OAuth provider configuration management.
 *
 * Actions:
 *   list_providers   – returns configured providers with masked secrets
 *   upsert_provider  – create or update a provider's OAuth credentials
 *   delete_provider   – remove a provider configuration
 *   test_provider    – test if credentials are valid (basic validation)
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

    // ── list_providers ───────────────────────────────────────────────────────
    if (action === 'list_providers') {
      const { data: rows, error } = await supabase
        .from('oauth_provider_configs')
        .select('id, provider, client_id, is_active, redirect_uri, created_at, updated_at')
        .order('provider')

      if (error) {
        console.error('list_providers error:', error)
        return json({ error: 'Failed to fetch provider configs' }, 500)
      }

      // Mask client_id to show only last 8 chars
      const providers = (rows ?? []).map((row: any) => ({
        ...row,
        client_id_masked: row.client_id
          ? '****' + row.client_id.slice(-8)
          : null,
        has_secret: true, // secret exists in DB but never exposed
      }))

      return json({ providers })
    }

    // ── upsert_provider ──────────────────────────────────────────────────────
    if (action === 'upsert_provider') {
      const provider = String(body.provider ?? '').toLowerCase()
      if (!['google', 'microsoft'].includes(provider)) {
        return json({ error: 'Provider must be "google" or "microsoft"' }, 400)
      }

      const clientId = String(body.client_id ?? '').trim()
      const clientSecret = String(body.client_secret ?? '').trim()

      if (!clientId || clientId.length < 10) {
        return json({ error: 'client_id is required (min 10 chars)' }, 400)
      }
      if (!clientSecret || clientSecret.length < 8) {
        return json({ error: 'client_secret is required (min 8 chars)' }, 400)
      }

      const redirectUri = body.redirect_uri
        ? String(body.redirect_uri).trim()
        : null

      // Check if provider already exists
      const { data: existing } = await supabase
        .from('oauth_provider_configs')
        .select('id, client_id, is_active')
        .eq('provider', provider)
        .maybeSingle()

      const isActive = body.is_active !== false

      const upsertPayload: Record<string, unknown> = {
        provider,
        client_id: clientId,
        client_secret: clientSecret,
        is_active: isActive,
        updated_at: new Date().toISOString(),
        updated_by: ctx.actor.id,
      }
      if (redirectUri) {
        upsertPayload.redirect_uri = redirectUri
      }

      const { data: result, error: upsertError } = await supabase
        .from('oauth_provider_configs')
        .upsert(upsertPayload, { onConflict: 'provider' })
        .select('id, provider, client_id, is_active, redirect_uri, created_at, updated_at')
        .single()

      if (upsertError) {
        console.error('upsert_provider error:', upsertError)
        return json({ error: 'Failed to save provider config' }, 500)
      }

      await writeAuditLog(supabase, {
        adminUserId: ctx.actor.id,
        action: existing ? 'update_oauth_provider' : 'create_oauth_provider',
        resourceType: 'oauth_provider_config',
        resourceId: result.id,
        oldValues: existing
          ? { client_id: '****' + existing.client_id.slice(-8), is_active: existing.is_active }
          : null,
        newValues: {
          provider,
          client_id: '****' + clientId.slice(-8),
          is_active: isActive,
        },
        description: `${existing ? 'Updated' : 'Created'} OAuth config for ${provider}`,
      })

      return json({
        provider: {
          ...result,
          client_id_masked: '****' + result.client_id.slice(-8),
          has_secret: true,
        },
        created: !existing,
      })
    }

    // ── delete_provider ──────────────────────────────────────────────────────
    if (action === 'delete_provider') {
      const provider = String(body.provider ?? '').toLowerCase()
      if (!['google', 'microsoft'].includes(provider)) {
        return json({ error: 'Provider must be "google" or "microsoft"' }, 400)
      }

      const { data: existing } = await supabase
        .from('oauth_provider_configs')
        .select('id, provider, client_id')
        .eq('provider', provider)
        .maybeSingle()

      if (!existing) {
        return json({ error: `No config found for provider: ${provider}` }, 404)
      }

      const { error: deleteError } = await supabase
        .from('oauth_provider_configs')
        .delete()
        .eq('provider', provider)

      if (deleteError) {
        console.error('delete_provider error:', deleteError)
        return json({ error: 'Failed to delete provider config' }, 500)
      }

      await writeAuditLog(supabase, {
        adminUserId: ctx.actor.id,
        action: 'delete_oauth_provider',
        resourceType: 'oauth_provider_config',
        resourceId: existing.id,
        oldValues: {
          provider: existing.provider,
          client_id: '****' + existing.client_id.slice(-8),
        },
        newValues: null,
        description: `Deleted OAuth config for ${provider}`,
      })

      return json({ deleted: true, provider })
    }

    // ── test_provider ────────────────────────────────────────────────────────
    if (action === 'test_provider') {
      const provider = String(body.provider ?? '').toLowerCase()
      if (!['google', 'microsoft'].includes(provider)) {
        return json({ error: 'Provider must be "google" or "microsoft"' }, 400)
      }

      const { data: config } = await supabase
        .from('oauth_provider_configs')
        .select('client_id, client_secret, is_active, redirect_uri')
        .eq('provider', provider)
        .maybeSingle()

      if (!config) {
        return json({
          provider,
          status: 'not_configured',
          message: `No OAuth credentials found for ${provider}`,
        })
      }

      if (!config.is_active) {
        return json({
          provider,
          status: 'disabled',
          message: `OAuth provider ${provider} is configured but disabled`,
        })
      }

      // Basic validation: check that client_id looks valid
      const checks: Record<string, boolean> = {
        has_client_id: !!config.client_id && config.client_id.length >= 10,
        has_client_secret: !!config.client_secret && config.client_secret.length >= 8,
        is_active: config.is_active,
      }

      if (provider === 'google') {
        checks.client_id_format = config.client_id.includes('.apps.googleusercontent.com')
      }

      const allPassed = Object.values(checks).every(Boolean)

      return json({
        provider,
        status: allPassed ? 'valid' : 'invalid',
        checks,
        message: allPassed
          ? `${provider} OAuth credentials look valid`
          : `Some checks failed for ${provider} — verify your credentials`,
      })
    }

    return json({ error: `Unknown action: ${action}` }, 400)

  } catch (thrown) {
    if (thrown instanceof Response) return thrown
    const msg = thrown instanceof Error ? thrown.message : String(thrown)
    console.error('admin-oauth-config error:', msg)
    return json({ error: msg || 'Internal server error' }, 500)
  }
})
