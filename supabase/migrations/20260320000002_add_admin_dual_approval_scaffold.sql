-- ============================================================================
-- Migration: Admin Dual Approval Scaffolding
-- Created: 2026-03-20
-- Purpose: Add approval request table used by critical admin operations
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.admin_approval_requests (
  id                    UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
  action_type           TEXT              NOT NULL,
  resource_type         TEXT              NOT NULL,
  resource_id           UUID,
  request_payload       JSONB             NOT NULL DEFAULT '{}'::jsonb,
  reason                TEXT,
  status                TEXT              NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  requested_by_user_id  UUID              NOT NULL REFERENCES app.users(id),
  approved_by_user_id   UUID              REFERENCES app.users(id),
  requested_at          TIMESTAMPTZ       NOT NULL DEFAULT now(),
  decided_at            TIMESTAMPTZ,
  expires_at            TIMESTAMPTZ       NOT NULL DEFAULT (now() + interval '24 hours')
);

ALTER TABLE app.admin_approval_requests ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'app'
      AND tablename = 'admin_approval_requests'
      AND policyname = 'deny_direct_access'
  ) THEN
    CREATE POLICY "deny_direct_access"
    ON app.admin_approval_requests
    FOR ALL
    TO anon, authenticated
    USING (false);
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_admin_approval_requests_status
  ON app.admin_approval_requests(status);

CREATE INDEX IF NOT EXISTS idx_admin_approval_requests_action
  ON app.admin_approval_requests(action_type, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_approval_requests_requester
  ON app.admin_approval_requests(requested_by_user_id, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_approval_requests_resource
  ON app.admin_approval_requests(resource_type, resource_id);
