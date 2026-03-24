import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from './cors.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!

// Log environment status at startup (without exposing secrets)
console.log('[admin.ts init] Environment check:', {
  SUPABASE_URL_exists: !!supabaseUrl,
  SUPABASE_URL_length: supabaseUrl?.length,
  SUPABASE_SERVICE_ROLE_KEY_exists: !!supabaseServiceKey,
  SUPABASE_ANON_KEY_exists: !!supabaseAnonKey,
})

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

export const ADMIN_PERMISSIONS = {
  viewDashboard: 'view_dashboard',
  viewHouseholds: 'view_households',
  manageHouseholds: 'manage_households',
  viewUsers: 'view_users',
  manageUsers: 'manage_users',
  moderateContent: 'moderate_content',
  manageSupportTickets: 'manage_support_tickets',
  manageStaff: 'manage_staff',
  manageFeatures: 'manage_features',
  viewAuditLogs: 'view_audit_logs',
  viewAnalytics: 'view_analytics',
  exportReports: 'export_reports',
  manageSecurity: 'manage_security',
} as const

export type AdminPermission = typeof ADMIN_PERMISSIONS[keyof typeof ADMIN_PERMISSIONS]

const ALL_ADMIN_PERMISSIONS = new Set(Object.values(ADMIN_PERMISSIONS))
const SUPPORT_DEFAULT_PERMISSIONS = new Set<AdminPermission>([
  ADMIN_PERMISSIONS.viewDashboard,
  ADMIN_PERMISSIONS.viewHouseholds,
  ADMIN_PERMISSIONS.viewUsers,
  ADMIN_PERMISSIONS.moderateContent,
  ADMIN_PERMISSIONS.manageSupportTickets,
  ADMIN_PERMISSIONS.viewAuditLogs,
  ADMIN_PERMISSIONS.viewAnalytics,
])

const CUSTOMER_SERVICE_DEFAULT_PERMISSIONS = new Set<AdminPermission>([
  ADMIN_PERMISSIONS.viewDashboard,
  ADMIN_PERMISSIONS.viewUsers,
  ADMIN_PERMISSIONS.manageUsers,
  ADMIN_PERMISSIONS.viewHouseholds,
  ADMIN_PERMISSIONS.manageSupportTickets,
  ADMIN_PERMISSIONS.viewAuditLogs,
])

const READER_DEFAULT_PERMISSIONS = new Set<AdminPermission>([
  ADMIN_PERMISSIONS.viewDashboard,
  ADMIN_PERMISSIONS.viewUsers,
  ADMIN_PERMISSIONS.viewHouseholds,
  ADMIN_PERMISSIONS.viewAnalytics,
  ADMIN_PERMISSIONS.viewAuditLogs,
])

const BILLING_SERVICE_DEFAULT_PERMISSIONS = new Set<AdminPermission>([
  ADMIN_PERMISSIONS.viewDashboard,
  ADMIN_PERMISSIONS.viewUsers,
  ADMIN_PERMISSIONS.viewAnalytics,
])

const ADMIN_DEFAULT_PERMISSIONS = new Set<AdminPermission>([
  ADMIN_PERMISSIONS.viewDashboard,
  ADMIN_PERMISSIONS.viewHouseholds,
  ADMIN_PERMISSIONS.manageHouseholds,
  ADMIN_PERMISSIONS.viewUsers,
  ADMIN_PERMISSIONS.manageUsers,
  ADMIN_PERMISSIONS.moderateContent,
  ADMIN_PERMISSIONS.manageSupportTickets,
  ADMIN_PERMISSIONS.manageFeatures,
  ADMIN_PERMISSIONS.viewAuditLogs,
  ADMIN_PERMISSIONS.viewAnalytics,
  ADMIN_PERMISSIONS.exportReports,
])

const STAFF_ROLES = new Set(['super_admin', 'admin', 'support_staff', 'customer_service', 'reader', 'billing_service'])

const DUAL_APPROVAL_DEFAULT_TTL_HOURS = 24

export type DualApprovalActionType =
  | 'assign_staff_role'
  | 'revoke_staff_role'
  | 'change_staff_scope'
  | 'critical_config_change'

interface ApprovalRequestRecord {
  id: string
  action_type: DualApprovalActionType
  status: 'pending' | 'approved' | 'rejected' | 'expired'
  requested_by_user_id: string
  approved_by_user_id: string | null
  expires_at: string | null
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
  options?: {
    requireSuperAdmin?: boolean
    requiredPermissions?: AdminPermission[]
  },
): Promise<AdminContext> {
  console.log('[requireAdmin] Starting authorization check')
  
  const authHeader = req.headers.get('Authorization') ?? ''
  console.log('[requireAdmin] Auth header present:', !!authHeader)
  console.log('[requireAdmin] Auth header format:', authHeader.slice(0, 20) + (authHeader.length > 20 ? '...' : ''))
  
  if (!authHeader.startsWith('Bearer ')) {
    console.error('[requireAdmin] Missing Bearer prefix')
    throw new Response(JSON.stringify({ error: 'Missing or malformed Authorization header' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  const token = authHeader.slice(7).trim()
  console.log('[requireAdmin] Token extracted, length:', token.length)
  // Log token structure for debugging
  const tokenParts = token.split('.')
  console.log('[requireAdmin] Token format: JWT parts:', tokenParts.length, 
    'first 8 chars:', token.slice(0, 8),
    'looks like JWT:', tokenParts.length === 3)

  // Verify token cryptographically using Supabase's own auth — same approach as auth-bootstrap
  console.log('[requireAdmin] Attempting token verification with anonClient...')
  let result
  try {
    result = await anonClient.auth.getUser(token)
  } catch (err) {
    console.error('[requireAdmin] Exception during getUser call:', err)
    throw json({ error: 'Token verification failed: ' + (err instanceof Error ? err.message : String(err)) }, 401)
  }
  
  console.log('[requireAdmin] getUser result:', {
    hasData: !!result.data,
    hasUser: !!result.data?.user,
    hasError: !!result.error,
    error: result.error,
    userId: result.data?.user?.id?.slice(0, 8) + '...',
  })
  
  const { data: { user: authUser } = {}, error: authError } = result
  if (authError || !authUser) {
    console.error('[requireAdmin] Token verification failed. Error:', authError, 'User:', authUser)
    throw json({ error: 'Invalid or expired token' }, 401)
  }

  console.log('[requireAdmin] Token verified for user:', authUser.id.slice(0, 8) + '...')

  const supabase = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { persistSession: false },
    db: { schema: 'app' },
  })

  console.log('[requireAdmin] Looking up user in database with firebase_uid:', authUser.id.slice(0, 8) + '...')
  const { data: actor, error } = await supabase
    .from('users')
    .select('id, email, role, household_id, staff_role, staff_scope, admin_permissions')
    .eq('firebase_uid', authUser.id)
    .is('deleted_at', null)
    .maybeSingle<AdminActor>()

  if (error) {
    console.error('[requireAdmin] Database lookup error:', error)
    throw json({ error: 'Failed to verify admin access' }, 500)
  }

  if (!actor) {
    console.error('[requireAdmin] User not found in database for firebase_uid:', authUser.id)
    throw json({ error: 'User not found' }, 404)
  }

  console.log('[requireAdmin] User found in database:', {
    id: actor.id.slice(0, 8) + '...',
    role: actor.role,
    staff_role: actor.staff_role,
    household_id: actor.household_id,
  })

  const isSuperAdmin = actor.role === 'super_admin' || actor.staff_role === 'super_admin'
  const isStaffMember = actor.staff_role != null && STAFF_ROLES.has(actor.staff_role)
  console.log('[requireAdmin] Role check:', { isSuperAdmin, isStaffMember, staff_role: actor.staff_role })

  if (options?.requireSuperAdmin) {
    if (!isSuperAdmin) {
      console.error('[requireAdmin] Super admin required but user is not super admin')
      throw json({ error: 'Super admin access required' }, 403)
    }
  } else if (!isSuperAdmin && !isStaffMember) {
    console.error('[requireAdmin] Admin access denied - user has no staff role')
    throw json({ error: 'Admin access denied' }, 403)
  }

  console.log('[requireAdmin] Authorization successful for user:', actor.id.slice(0, 8) + '...')
  
  const context: AdminContext = {
    supabase,
    actor,
    scope: isSuperAdmin ? 'global' : actor.staff_scope ?? actor.household_id ?? 'none',
    isSuperAdmin,
  }

  if (options?.requiredPermissions && options.requiredPermissions.length > 0) {
    requireAdminPermissions(context, options.requiredPermissions)
  }

  return context
}

function actorExplicitPermissions(actor: AdminActor): Set<AdminPermission> {
  const result = new Set<AdminPermission>()
  const raw = actor.admin_permissions
  if (!raw || typeof raw !== 'object') {
    return result
  }

  for (const [key, value] of Object.entries(raw)) {
    if (value === true && ALL_ADMIN_PERMISSIONS.has(key as AdminPermission)) {
      result.add(key as AdminPermission)
    }
  }

  return result
}

export function hasAdminPermission(actor: AdminActor, permission: AdminPermission): boolean {
  if (actor.role === 'super_admin' || actor.staff_role === 'super_admin') {
    return true
  }

  if (!ALL_ADMIN_PERMISSIONS.has(permission)) {
    return false
  }

  const explicit = actorExplicitPermissions(actor)
  if (explicit.size > 0) {
    return explicit.has(permission)
  }

  // Check role-based defaults
  switch (actor.staff_role) {
    case 'admin':
      return ADMIN_DEFAULT_PERMISSIONS.has(permission)
    case 'support_staff':
      return SUPPORT_DEFAULT_PERMISSIONS.has(permission)
    case 'customer_service':
      return CUSTOMER_SERVICE_DEFAULT_PERMISSIONS.has(permission)
    case 'reader':
      return READER_DEFAULT_PERMISSIONS.has(permission)
    case 'billing_service':
      return BILLING_SERVICE_DEFAULT_PERMISSIONS.has(permission)
    default:
      return false
  }
}

export function requireAdminPermissions(context: AdminContext, permissions: AdminPermission[]): void {
  for (const permission of permissions) {
    if (!hasAdminPermission(context.actor, permission)) {
      throw json(
        {
          error: 'Admin permission denied',
          missing_permission: permission,
        },
        403,
      )
    }
  }
}

function isDualApprovalEnforced(): boolean {
  return (Deno.env.get('ADMIN_DUAL_APPROVAL_ENFORCED') ?? '').toLowerCase() === 'true'
}

export async function requestDualApproval(
  context: AdminContext,
  payload: {
    actionType: DualApprovalActionType
    resourceType: string
    resourceId?: string | null
    reason?: string | null
    requestPayload?: Record<string, unknown>
    expiresInHours?: number
  },
): Promise<string> {
  const expiresHours = Number.isFinite(payload.expiresInHours)
    ? Math.max(1, Math.min(168, Math.trunc(payload.expiresInHours!)))
    : DUAL_APPROVAL_DEFAULT_TTL_HOURS

  const expiresAt = new Date(Date.now() + expiresHours * 60 * 60 * 1000).toISOString()

  const { data, error } = await context.supabase
    .from('admin_approval_requests')
    .insert({
      action_type: payload.actionType,
      resource_type: payload.resourceType,
      resource_id: payload.resourceId ?? null,
      request_payload: payload.requestPayload ?? {},
      reason: payload.reason ?? null,
      status: 'pending',
      requested_by_user_id: context.actor.id,
      expires_at: expiresAt,
    })
    .select('id')
    .single<{ id: string }>()

  if (error || !data) {
    console.error('requestDualApproval insert error:', error)
    throw json({ error: 'Failed to create approval request' }, 500)
  }

  return data.id
}

export async function verifyDualApproval(
  context: AdminContext,
  payload: {
    approvalRequestId: string
    expectedActionType: DualApprovalActionType
  },
): Promise<void> {
  const { data, error } = await context.supabase
    .from('admin_approval_requests')
    .select('id, action_type, status, requested_by_user_id, approved_by_user_id, expires_at')
    .eq('id', payload.approvalRequestId)
    .maybeSingle<ApprovalRequestRecord>()

  if (error) {
    console.error('verifyDualApproval lookup error:', error)
    throw json({ error: 'Failed to validate approval request' }, 500)
  }

  if (!data) {
    throw json({ error: 'Approval request not found' }, 404)
  }

  if (data.action_type !== payload.expectedActionType) {
    throw json({ error: 'Approval request does not match action type' }, 400)
  }

  if (data.status !== 'approved') {
    throw json({ error: 'Approval request is not approved' }, 403)
  }

  if (data.requested_by_user_id === context.actor.id) {
    throw json({ error: 'Requester cannot execute their own approval request' }, 403)
  }

  if (data.approved_by_user_id == null) {
    throw json({ error: 'Approval request missing approver' }, 403)
  }

  if (data.approved_by_user_id === context.actor.id) {
    throw json({ error: 'Approver cannot execute approved action' }, 403)
  }

  if (data.expires_at && new Date(data.expires_at).getTime() < Date.now()) {
    throw json({ error: 'Approval request has expired' }, 403)
  }
}

export async function ensureDualApproval(
  context: AdminContext,
  payload: {
    actionType: DualApprovalActionType
    resourceType: string
    resourceId?: string | null
    reason?: string | null
    requestPayload?: Record<string, unknown>
    approvalRequestId?: string | null
    force?: boolean
  },
): Promise<void> {
  const shouldEnforce = payload.force === true || isDualApprovalEnforced()
  if (!shouldEnforce) {
    return
  }

  if (payload.approvalRequestId) {
    await verifyDualApproval(context, {
      approvalRequestId: payload.approvalRequestId,
      expectedActionType: payload.actionType,
    })
    return
  }

  const requestId = await requestDualApproval(context, {
    actionType: payload.actionType,
    resourceType: payload.resourceType,
    resourceId: payload.resourceId,
    reason: payload.reason,
    requestPayload: payload.requestPayload,
  })

  throw json(
    {
      requires_approval: true,
      approval_request_id: requestId,
      approval_action_type: payload.actionType,
      message: 'Dual approval required before this action can be executed',
    },
    202,
  )
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