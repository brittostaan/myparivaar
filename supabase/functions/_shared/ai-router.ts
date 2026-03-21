/**
 * AI Router — reads task assignments from DB and routes to the correct
 * provider API (OpenAI, Anthropic, or Gemini).
 *
 * Usage:
 *   import { routeAIRequest } from '../_shared/ai-router.ts'
 *   const result = await routeAIRequest(supabase, 'financial_chat', messages, { max_tokens: 250 })
 */

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant'
  content: string
}

export interface AIRequestOptions {
  max_tokens?: number
  temperature?: number
}

export interface AIResponse {
  content: string
  model: string
  provider: string
}

interface TaskConfig {
  providerName: string
  baseUrl: string
  modelName: string
  apiKey: string
}

/**
 * Look up the task assignment + active key from DB.
 * Falls back to the legacy OPENAI_API_KEY env var when no key is stored.
 */
async function resolveTask(
  supabase: SupabaseClient,
  taskSlug: string,
): Promise<TaskConfig> {
  const { data: task, error } = await supabase
    .from('ai_task_assignments')
    .select(`
      provider_id, model_name, is_active,
      ai_providers(name, base_url)
    `)
    .eq('task_slug', taskSlug)
    .single()

  if (error || !task) {
    throw new Error(`AI task "${taskSlug}" not found`)
  }

  if (!task.is_active) {
    throw new Error(`AI task "${taskSlug}" is disabled`)
  }

  const provider = (task as any).ai_providers
  if (!provider || !task.provider_id || !task.model_name) {
    // Fallback: use legacy env var with OpenAI defaults
    const legacyKey = Deno.env.get('OPENAI_API_KEY')
    if (!legacyKey) {
      throw new Error(`AI task "${taskSlug}" has no provider/model assigned and no legacy key`)
    }
    return {
      providerName: 'openai',
      baseUrl: 'https://api.openai.com/v1',
      modelName: 'gpt-3.5-turbo',
      apiKey: legacyKey,
    }
  }

  // Get an active key for this provider
  const { data: keyRow } = await supabase
    .from('ai_provider_keys')
    .select('api_key')
    .eq('provider_id', task.provider_id)
    .eq('is_active', true)
    .limit(1)
    .single()

  if (!keyRow?.api_key) {
    // Fallback to legacy env var if provider is openai
    if (provider.name === 'openai') {
      const legacyKey = Deno.env.get('OPENAI_API_KEY')
      if (legacyKey) {
        return {
          providerName: 'openai',
          baseUrl: provider.base_url,
          modelName: task.model_name,
          apiKey: legacyKey,
        }
      }
    }
    throw new Error(`No active API key for provider "${provider.display_name}"`)
  }

  return {
    providerName: provider.name,
    baseUrl: provider.base_url,
    modelName: task.model_name,
    apiKey: keyRow.api_key,
  }
}

// ── Provider-specific callers ───────────────────────────────────

async function callOpenAI(
  config: TaskConfig,
  messages: ChatMessage[],
  opts: AIRequestOptions,
): Promise<string> {
  const res = await fetch(`${config.baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: config.modelName,
      messages,
      max_tokens: opts.max_tokens ?? 300,
      temperature: opts.temperature ?? 0.7,
    }),
  })

  const data = await res.json()

  if (!res.ok) {
    throw new Error(`OpenAI API error ${res.status}: ${JSON.stringify(data)}`)
  }

  return data.choices?.[0]?.message?.content?.trim() ?? ''
}

async function callAnthropic(
  config: TaskConfig,
  messages: ChatMessage[],
  opts: AIRequestOptions,
): Promise<string> {
  // Anthropic separates system from messages
  const systemMsg = messages.find((m) => m.role === 'system')
  const userMessages = messages.filter((m) => m.role !== 'system')

  const body: Record<string, unknown> = {
    model: config.modelName,
    max_tokens: opts.max_tokens ?? 300,
    messages: userMessages.map((m) => ({ role: m.role, content: m.content })),
  }
  if (systemMsg) {
    body.system = systemMsg.content
  }

  const res = await fetch(`${config.baseUrl}/messages`, {
    method: 'POST',
    headers: {
      'x-api-key': config.apiKey,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })

  const data = await res.json()

  if (!res.ok) {
    throw new Error(`Anthropic API error ${res.status}: ${JSON.stringify(data)}`)
  }

  return data.content?.[0]?.text?.trim() ?? ''
}

async function callGemini(
  config: TaskConfig,
  messages: ChatMessage[],
  opts: AIRequestOptions,
): Promise<string> {
  // Map messages to Gemini format
  const systemMsg = messages.find((m) => m.role === 'system')
  const nonSystemMessages = messages.filter((m) => m.role !== 'system')

  const contents = nonSystemMessages.map((m) => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content }],
  }))

  const body: Record<string, unknown> = {
    contents,
    generationConfig: {
      maxOutputTokens: opts.max_tokens ?? 300,
      temperature: opts.temperature ?? 0.7,
    },
  }
  if (systemMsg) {
    body.systemInstruction = { parts: [{ text: systemMsg.content }] }
  }

  const res = await fetch(
    `${config.baseUrl}/models/${config.modelName}:generateContent?key=${config.apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    },
  )

  const data = await res.json()

  if (!res.ok) {
    throw new Error(`Gemini API error ${res.status}: ${JSON.stringify(data)}`)
  }

  return data.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? ''
}

// ── Public entry point ──────────────────────────────────────────

export async function routeAIRequest(
  supabase: SupabaseClient,
  taskSlug: string,
  messages: ChatMessage[],
  opts: AIRequestOptions = {},
): Promise<AIResponse> {
  const config = await resolveTask(supabase, taskSlug)

  let content: string

  switch (config.providerName) {
    case 'openai':
      content = await callOpenAI(config, messages, opts)
      break
    case 'anthropic':
      content = await callAnthropic(config, messages, opts)
      break
    case 'gemini':
      content = await callGemini(config, messages, opts)
      break
    default:
      throw new Error(`Unsupported provider: ${config.providerName}`)
  }

  return {
    content,
    model: config.modelName,
    provider: config.providerName,
  }
}
