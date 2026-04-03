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

/** Known models per provider for the list_models action. */
const PROVIDER_MODELS: Record<string, string[]> = {
  openai: [
    'gpt-4o',
    'gpt-4o-mini',
    'gpt-4-turbo',
    'gpt-4',
    'gpt-3.5-turbo',
    'o3-mini',
  ],
  anthropic: [
    'claude-sonnet-4-20250514',
    'claude-3-5-haiku-20241022',
    'claude-3-opus-20240229',
  ],
  gemini: [
    'gemini-2.0-flash',
    'gemini-1.5-pro',
    'gemini-1.5-flash',
  ],
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  try {
    const { supabase, actor } = await requireAdmin(req, {
      requiredPermissions: [ADMIN_PERMISSIONS.manageFeatures],
    })

    const body = await parseBody(req)
    const action = typeof body.action === 'string' ? body.action.trim() : ''
    const userAgent = req.headers.get('user-agent')
    const ipAddress = pickClientIp(req)

    // ── list_providers ──────────────────────────────────────────
    if (action === 'list_providers') {
      const { data, error } = await supabase
        .from('ai_providers')
        .select('id, name, display_name, base_url, is_active, created_at')
        .order('created_at')

      if (error) {
        console.error('list_providers error:', error)
        return json({ error: 'Failed to list providers' }, 500)
      }

      return json({ providers: data ?? [] })
    }

    // ── list_keys ───────────────────────────────────────────────
    if (action === 'list_keys') {
      const { data, error } = await supabase
        .from('ai_provider_keys')
        .select(`
          id, provider_id, label, is_active, created_at, updated_at,
          ai_providers!inner(name, display_name)
        `)
        .order('created_at')

      if (error) {
        console.error('list_keys error:', error)
        return json({ error: 'Failed to list keys' }, 500)
      }

      // Mask API keys — never return the actual key
      const keys = (data ?? []).map((k: any) => ({
        id: k.id,
        provider_id: k.provider_id,
        provider_name: k.ai_providers?.name,
        provider_display_name: k.ai_providers?.display_name,
        label: k.label,
        is_active: k.is_active,
        created_at: k.created_at,
        updated_at: k.updated_at,
      }))

      return json({ keys })
    }

    // ── add_key ─────────────────────────────────────────────────
    if (action === 'add_key') {
      const providerId = typeof body.provider_id === 'string' ? body.provider_id.trim() : ''
      const apiKey = typeof body.api_key === 'string' ? body.api_key.trim() : ''
      const label = typeof body.label === 'string' ? body.label.trim() : 'default'

      if (!providerId || !apiKey) {
        return json({ error: 'provider_id and api_key are required' }, 400)
      }

      // Verify provider exists
      const { data: provider } = await supabase
        .from('ai_providers')
        .select('id, name')
        .eq('id', providerId)
        .single()

      if (!provider) {
        return json({ error: 'Provider not found' }, 404)
      }

      const { data: newKey, error: insertError } = await supabase
        .from('ai_provider_keys')
        .insert({ provider_id: providerId, api_key: apiKey, label })
        .select('id, provider_id, label, is_active, created_at')
        .single()

      if (insertError) {
        console.error('add_key error:', insertError)
        return json({ error: 'Failed to add key' }, 500)
      }

      await writeAuditLog(supabase, {
        actorId: actor.id,
        action: 'ai_key_added',
        resourceType: 'ai_provider_key',
        resourceId: newKey.id,
        metadata: { provider: provider.name, label },
        ipAddress,
        userAgent,
      })

      return json({ key: newKey })
    }

    // ── remove_key ──────────────────────────────────────────────
    if (action === 'remove_key') {
      const keyId = typeof body.key_id === 'string' ? body.key_id.trim() : ''

      if (!keyId) {
        return json({ error: 'key_id is required' }, 400)
      }

      const { data: existing } = await supabase
        .from('ai_provider_keys')
        .select('id, provider_id, label')
        .eq('id', keyId)
        .single()

      if (!existing) {
        return json({ error: 'Key not found' }, 404)
      }

      const { error: delError } = await supabase
        .from('ai_provider_keys')
        .delete()
        .eq('id', keyId)

      if (delError) {
        console.error('remove_key error:', delError)
        return json({ error: 'Failed to remove key' }, 500)
      }

      await writeAuditLog(supabase, {
        actorId: actor.id,
        action: 'ai_key_removed',
        resourceType: 'ai_provider_key',
        resourceId: keyId,
        metadata: { label: existing.label },
        ipAddress,
        userAgent,
      })

      return json({ success: true })
    }

    // ── test_key ────────────────────────────────────────────────
    if (action === 'test_key') {
      const keyId = typeof body.key_id === 'string' ? body.key_id.trim() : ''

      if (!keyId) {
        return json({ error: 'key_id is required' }, 400)
      }

      const { data: keyRow } = await supabase
        .from('ai_provider_keys')
        .select('id, api_key, provider_id, label')
        .eq('id', keyId)
        .single()

      if (!keyRow) {
        return json({ error: 'Key not found' }, 404)
      }

      const { data: provider } = await supabase
        .from('ai_providers')
        .select('name, base_url')
        .eq('id', keyRow.provider_id)
        .single()

      if (!provider) {
        return json({ error: 'Provider not found' }, 404)
      }

      let valid = false
      let message = ''

      try {
        if (provider.name === 'openai') {
          const res = await fetch(`${provider.base_url}/models`, {
            headers: { Authorization: `Bearer ${keyRow.api_key}` },
          })
          valid = res.ok
          message = valid ? 'Key is valid' : `Invalid key (HTTP ${res.status})`
        } else if (provider.name === 'anthropic') {
          const res = await fetch(`${provider.base_url}/messages`, {
            method: 'POST',
            headers: {
              'x-api-key': keyRow.api_key,
              'anthropic-version': '2023-06-01',
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              model: 'claude-3-5-haiku-20241022',
              max_tokens: 1,
              messages: [{ role: 'user', content: 'Hi' }],
            }),
          })
          // 200 or 400 (bad request) means key itself is valid
          valid = res.status !== 401 && res.status !== 403
          message = valid ? 'Key is valid' : `Invalid key (HTTP ${res.status})`
        } else if (provider.name === 'gemini') {
          const res = await fetch(
            `${provider.base_url}/models?key=${keyRow.api_key}`
          )
          valid = res.ok
          message = valid ? 'Key is valid' : `Invalid key (HTTP ${res.status})`
        } else {
          message = 'Unknown provider — cannot test'
        }
      } catch (err) {
        message = `Connection error: ${(err as Error).message}`
      }

      await writeAuditLog(supabase, {
        actorId: actor.id,
        action: 'ai_key_tested',
        resourceType: 'ai_provider_key',
        resourceId: keyId,
        metadata: { provider: provider.name, valid, message },
        ipAddress,
        userAgent,
      })

      return json({ valid, message })
    }

    // ── list_tasks ──────────────────────────────────────────────
    if (action === 'list_tasks') {
      const { data, error } = await supabase
        .from('ai_task_assignments')
        .select(`
          id, task_slug, display_name, description,
          provider_id, model_name, is_active,
          created_at, updated_at,
          ai_providers(name, display_name)
        `)
        .order('created_at')

      if (error) {
        console.error('list_tasks error:', error)
        return json({ error: 'Failed to list tasks' }, 500)
      }

      const tasks = (data ?? []).map((t: any) => ({
        id: t.id,
        task_slug: t.task_slug,
        display_name: t.display_name,
        description: t.description,
        provider_id: t.provider_id,
        provider_name: t.ai_providers?.name,
        provider_display_name: t.ai_providers?.display_name,
        model_name: t.model_name,
        is_active: t.is_active,
        created_at: t.created_at,
        updated_at: t.updated_at,
      }))

      return json({ tasks })
    }

    // ── assign_model ────────────────────────────────────────────
    if (action === 'assign_model') {
      const taskId = typeof body.task_id === 'string' ? body.task_id.trim() : ''
      const providerId = body.provider_id != null
        ? (typeof body.provider_id === 'string' ? body.provider_id.trim() : '')
        : null
      const modelName = body.model_name != null
        ? (typeof body.model_name === 'string' ? body.model_name.trim() : '')
        : null
      const isActive = typeof body.is_active === 'boolean' ? body.is_active : undefined

      if (!taskId) {
        return json({ error: 'task_id is required' }, 400)
      }

      const updatePayload: Record<string, unknown> = { updated_at: new Date().toISOString() }
      if (providerId !== undefined) updatePayload.provider_id = providerId || null
      if (modelName !== undefined) updatePayload.model_name = modelName || null
      if (isActive !== undefined) updatePayload.is_active = isActive

      const { data: updated, error: updateError } = await supabase
        .from('ai_task_assignments')
        .update(updatePayload)
        .eq('id', taskId)
        .select('id, task_slug, provider_id, model_name, is_active')
        .single()

      if (updateError) {
        console.error('assign_model error:', updateError)
        return json({ error: 'Failed to assign model' }, 500)
      }

      if (!updated) {
        return json({ error: 'Task not found' }, 404)
      }

      await writeAuditLog(supabase, {
        actorId: actor.id,
        action: 'ai_task_assigned',
        resourceType: 'ai_task_assignment',
        resourceId: updated.id,
        metadata: {
          task_slug: updated.task_slug,
          provider_id: updated.provider_id,
          model_name: updated.model_name,
          is_active: updated.is_active,
        },
        ipAddress,
        userAgent,
      })

      return json({ task: updated })
    }

    // ── list_models ─────────────────────────────────────────────
    if (action === 'list_models') {
      const providerName = typeof body.provider_name === 'string' ? body.provider_name.trim() : ''

      if (providerName && PROVIDER_MODELS[providerName]) {
        return json({ models: PROVIDER_MODELS[providerName] })
      }

      return json({ models: PROVIDER_MODELS })
    }

    return json({ error: `Unknown action: ${action}` }, 400)
  } catch (err) {
    if (err instanceof Response) return err
    console.error('admin-ai-config error:', err)
    return json({ error: 'Internal server error' }, 500)
  }
})
