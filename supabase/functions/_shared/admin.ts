import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from './cors.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!

// Anon client used solely for JWT verification via auth.getUser()
const anonClient = createClient(supabaseUrl, supabaseAnonKey, {
  auth: { persistSession: false },
})

export interface AdminActor {
  id: string
  email: string
  role: string
  household_id: string | null
  staff_role: string | null
  staff_scope: string | null
  admin_permissions: Record<string, unknown> | null
}

export interface AdminContext {
  supabase: ReturnType<typeof createClient>
  actor: AdminActor
  scope: string
  isSuperAdmin: boolean
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

export function parseBody(req: Request): Promise<Record<string, unknown>> {
  return req.json().catch(() => {
    throw new Error('Invalid JSON body')
  })
}

export async function requireAdmin(
  req: Request,
  options?: { requireSuperAdmin?: boolean },
): Promise<AdminContext> {
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader.startsWith('Bearer ')) {
    throw new Response(JSON.stringify({ error: 'Missing or malformed Authorization header' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  const token = authHeader.slice(7).trim()

  // Verify token cryptographically using Supabase's own auth — same approach as auth-bootstrap
  const { data: { user: authUser }, error: authError } = await anonClient.auth.getUser(token)
  if (authError || !authUser) {
    console.error('admin token verification failed:', authError)
    throw json({ error: 'Invalid or expired token' }, 401)
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { persistSession: false },
    db: { schema: 'app' },
  })

  const { data: actor, error } = await supabase
    .from('users')
    .select('id, email, role, household_id, staff_role, staff_scope, admin_permissions')
    .eq('firebase_uid', authUser.id)
    .is('deleted_at', null)
    .maybeSingle<AdminActor>()

  if (error) {
    console.error('admin auth lookup error:', error)
    throw json({ error: 'Failed to verify admin access' }, 500)
  }

  if (!actor) {
    throw json({ error: 'User not found' }, 404)
  }

  const isSuperAdmin = actor.role === 'super_admin' || actor.staff_role === 'super_admin'
  const isSupportStaff = actor.staff_role === 'support_staff'

  if (options?.requireSuperAdmin) {
    if (!isSuperAdmin) {
      throw json({ error: 'Super admin access required' }, 403)
    }
  } else if (!isSuperAdmin && !isSupportStaff) {
    throw json({ error: 'Admin access denied' }, 403)
  }

  return {
    supabase,
    actor,
    scope: isSuperAdmin ? 'global' : actor.staff_scope ?? actor.household_id ?? 'none',
    isSuperAdmin,
  }
}

export async function writeAuditLog(
  supabase: ReturnType<typeof createClient>,
  payload: {
    adminUserId: string
    action: string
    resourceType: string
    resourceId?: string | null
    oldValues?: Record<string, unknown> | null
    newValues?: Record<string, unknown> | null
    description?: string | null
    ipAddress?: string | null
    userAgent?: string | null
  },
): Promise<void> {
  const { error } = await supabase.from('audit_logs').insert({
    admin_user_id: payload.adminUserId,
    action: payload.action,
    resource_type: payload.resourceType,
    resource_id: payload.resourceId ?? null,
    old_values: payload.oldValues ?? null,
    new_values: payload.newValues ?? null,
    description: payload.description ?? null,
    ip_address: payload.ipAddress ?? null,
    user_agent: payload.userAgent ?? null,
  })

  if (error) {
    console.error('audit log write error:', error)
  }
}

export async function getScopedResourceIds(
  supabase: ReturnType<typeof createClient>,
  householdId: string,
): Promise<{ userIds: Set<string>; subscriptionIds: Set<string> }> {
  const [{ data: users, error: usersError }, { data: subscriptions, error: subscriptionsError }] = await Promise.all([
    supabase
      .from('users')
      .select('id')
      .eq('household_id', householdId)
      .is('deleted_at', null),
    supabase
      .from('subscriptions')
      .select('id')
      .eq('household_id', householdId)
      .is('deleted_at', null),
  ])

  if (usersError) {
    throw json({ error: 'Failed to load scoped users' }, 500)
  }
  if (subscriptionsError) {
    throw json({ error: 'Failed to load scoped subscriptions' }, 500)
  }

  return {
    userIds: new Set((users ?? []).map((item) => item.id as string)),
    subscriptionIds: new Set((subscriptions ?? []).map((item) => item.id as string)),
  }
}

export function isLogVisibleToScope(
  log: { resource_type: string; resource_id: string | null },
  householdId: string,
  scopedIds: { userIds: Set<string>; subscriptionIds: Set<string> },
): boolean {
  if (log.resource_type === 'household') {
    return log.resource_id === householdId
  }

  if (log.resource_type === 'user') {
    return log.resource_id != null && scopedIds.userIds.has(log.resource_id)
  }

  if (log.resource_type === 'subscription') {
    return log.resource_id != null && scopedIds.subscriptionIds.has(log.resource_id)
  }

  return false
}