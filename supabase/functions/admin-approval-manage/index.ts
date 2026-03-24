import {
  ADMIN_PERMISSIONS,
  type AdminContext,
  json,
  parseBody,
  requireAdmin,
  writeAuditLog,
} from '../_shared/admin.ts'
import { corsHeaders } from '../_shared/cors.ts'

declare const Deno: {
  env: { get(name: string): string | undefined }
  serve(handler: (req: Request) => Response | Promise<Response>): void
}

type ApprovalStatus = 'pending' | 'approved' | 'rejected' | 'expired'

type ApprovalRequestRow = {
  id: string
  action_type: string
  resource_type: string
  resource_id: string | null
  request_payload: Record<string, unknown>
  reason: string | null
  status: ApprovalStatus
  requested_by_user_id: string
  approved_by_user_id: string | null
  requested_at: string
  decided_at: string | null
  expires_at: string | null
}

function parseLimit(value: unknown, fallback = 100): number {
  const n = Number(value)
  if (!Number.isFinite(n)) {
    return fallback
  }
  return Math.max(1, Math.min(200, Math.trunc(n)))
}

function pickClientIp(req: Request): string | null {
  const forwarded = req.headers.get('x-forwarded-for')
  if (!forwarded) {
    return null
  }
  return forwarded.split(',')[0]?.trim() ?? null
}

async function fetchRequests(
  supabase: AdminContext['supabase'],
  payload: {
    status?: ApprovalStatus
    actionType?: string
    limit: number
  },
): Promise<ApprovalRequestRow[]> {
  let query = supabase
    .from('admin_approval_requests')
    .select('id, action_type, resource_type, resource_id, request_payload, reason, status, requested_by_user_id, approved_by_user_id, requested_at, decided_at, expires_at')
    .order('requested_at', { ascending: false })
    .limit(payload.limit)

  if (payload.status) {
    query = query.eq('status', payload.status)
  }

  if (payload.actionType) {
    query = query.eq('action_type', payload.actionType)
  }

  const { data, error } = await query
  if (error) {
    console.error('admin-approval-manage list error:', error)
    throw json({ error: 'Failed to fetch approval requests' }, 500)
  }

  return (data ?? []) as ApprovalRequestRow[]
}

async function enrichWithEmails(
  supabase: AdminContext['supabase'],
  requests: ApprovalRequestRow[],
): Promise<Array<ApprovalRequestRow & { requested_by_email: string; approved_by_email: string | null }>> {
  const userIds = new Set<string>()
  for (const request of requests) {
    userIds.add(request.requested_by_user_id)
    if (request.approved_by_user_id) {
      userIds.add(request.approved_by_user_id)
    }
  }

  if (userIds.size === 0) {
    return requests.map((request) => ({
      ...request,
      requested_by_email: 'Unknown',
      approved_by_email: null,
    }))
  }

  const { data: users, error } = await supabase
    .from('users')
    .select('id, email')
    .in('id', Array.from(userIds))

  if (error) {
    console.error('admin-approval-manage user lookup error:', error)
    throw json({ error: 'Failed to load requester metadata' }, 500)
  }

  type UserEmailRow = { id: string; email: string | null }
  const userRows = (users ?? []) as UserEmailRow[]
  const emailById = new Map<string, string>(
    userRows.map((row: UserEmailRow) => [row.id, row.email ?? 'Unknown']),
  )

  return requests.map((request) => ({
    ...request,
    requested_by_email: emailById.get(request.requested_by_user_id) ?? 'Unknown',
    approved_by_email: request.approved_by_user_id
      ? emailById.get(request.approved_by_user_id) ?? 'Unknown'
      : null,
  }))
}

function parseStatus(value: unknown): ApprovalStatus | undefined {
  const raw = typeof value === 'string' ? value.trim().toLowerCase() : ''
  if (raw === 'pending' || raw === 'approved' || raw === 'rejected' || raw === 'expired') {
    return raw
  }
  return undefined
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
      requiredPermissions: [ADMIN_PERMISSIONS.manageSecurity],
    })
    const { supabase, actor } = context
    const ipAddress = pickClientIp(req)
    const userAgent = req.headers.get('user-agent')

    const body = await parseBody(req)
    const action = typeof body.action === 'string' ? body.action.trim() : ''

    if (action === 'list') {
      const status = parseStatus(body.status)
      const actionType = typeof body.action_type === 'string' ? body.action_type.trim() : undefined
      const limit = parseLimit(body.limit, 100)

      const requests = await fetchRequests(supabase, {
        status,
        actionType,
        limit,
      })

      const enriched = await enrichWithEmails(supabase, requests)
      return json({ approval_requests: enriched })
    }

    if (action === 'approve' || action === 'reject') {
      if (!context.isSuperAdmin) {
        return json({ error: 'Super admin access required' }, 403)
      }

      const approvalRequestId =
        typeof body.approval_request_id === 'string' ? body.approval_request_id.trim() : ''
      if (!approvalRequestId) {
        return json({ error: 'approval_request_id is required' }, 400)
      }

      const { data: approval, error: lookupError } = await supabase
        .from('admin_approval_requests')
        .select('id, action_type, resource_type, resource_id, request_payload, reason, status, requested_by_user_id, approved_by_user_id, requested_at, decided_at, expires_at')
        .eq('id', approvalRequestId)
        .maybeSingle<ApprovalRequestRow>()

      if (lookupError) {
        console.error('admin-approval-manage lookup error:', lookupError)
        return json({ error: 'Failed to fetch approval request' }, 500)
      }

      if (!approval) {
        return json({ error: 'Approval request not found' }, 404)
      }

      if (approval.status !== 'pending') {
        return json(
          {
            error: `Cannot ${action} a ${approval.status} request`,
            current_status: approval.status,
          },
          409,
        )
      }

      if (approval.expires_at && new Date(approval.expires_at).getTime() < Date.now()) {
        return json(
          {
            error: 'Approval request has expired',
            current_status: 'expired',
            expired_at: approval.expires_at,
          },
          409,
        )
      }

      if (approval.requested_by_user_id === actor.id) {
        // Allow self-approval only when there's no other super admin available
        const { data: otherSuperAdmins, error: saError } = await supabase
          .from('users')
          .select('id')
          .or('role.eq.super_admin,staff_role.eq.super_admin')
          .neq('id', actor.id)
          .is('deleted_at', null)
          .limit(1)

        if (saError) {
          console.error('admin-approval-manage super admin count error:', saError)
        }

        if (otherSuperAdmins && otherSuperAdmins.length > 0) {
          return json({ error: 'You cannot approve your own request. Another super admin must approve it.' }, 403)
        }
        // Only one super admin exists — allow self-approval
      }

      const nextStatus: ApprovalStatus = action === 'approve' ? 'approved' : 'rejected'

      const { error: updateError } = await supabase
        .from('admin_approval_requests')
        .update({
          status: nextStatus,
          approved_by_user_id: actor.id,
          decided_at: new Date().toISOString(),
        })
        .eq('id', approvalRequestId)

      if (updateError) {
        console.error('admin-approval-manage update error:', updateError)
        return json({ error: 'Failed to update approval request' }, 500)
      }

      const { data: updated, error: updatedError } = await supabase
        .from('admin_approval_requests')
        .select('id, action_type, resource_type, resource_id, request_payload, reason, status, requested_by_user_id, approved_by_user_id, requested_at, decided_at, expires_at')
        .eq('id', approvalRequestId)
        .maybeSingle<ApprovalRequestRow>()

      if (updatedError || !updated) {
        console.error('admin-approval-manage fetch updated error:', updatedError)
        return json({ error: 'Approval request updated but failed to load result' }, 500)
      }

      const enriched = await enrichWithEmails(supabase, [updated])

      await writeAuditLog(supabase, {
        adminUserId: actor.id,
        action,
        resourceType: 'approval_request',
        resourceId: approvalRequestId,
        oldValues: {
          status: approval.status,
          approved_by_user_id: approval.approved_by_user_id,
          decided_at: approval.decided_at,
        },
        newValues: {
          status: nextStatus,
          approved_by_user_id: actor.id,
        },
        description: `${action === 'approve' ? 'Approved' : 'Rejected'} approval request for ${approval.action_type}`,
        ipAddress,
        userAgent,
      })

      return json({ approval_request: enriched[0] })
    }

    return json({ error: 'Unsupported action' }, 400)
  } catch (error) {
    if (error instanceof Response) {
      return error
    }

    console.error('admin-approval-manage error:', error)
    return json({ error: 'Internal server error' }, 500)
  }
})
