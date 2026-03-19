-- ============================================================================
-- Migration: Admin Infrastructure Setup
-- Created: 2026-03-19
-- Purpose: Add staff roles, permissions tracking, and audit logging
-- ============================================================================

-- ============================================================================
-- 1. Extend app.users with admin staff fields
-- ============================================================================

-- Add staff role column (null for regular users)
ALTER TABLE app.users
  ADD COLUMN IF NOT EXISTS staff_role TEXT 
    CHECK (staff_role IN ('super_admin', 'support_staff', NULL));

-- Add staff scope column: 'global' for platform-wide, specific household_id for scoped
ALTER TABLE app.users
  ADD COLUMN IF NOT EXISTS staff_scope TEXT;

-- Add permissions JSON (flexible permissions structure)
ALTER TABLE app.users
  ADD COLUMN IF NOT EXISTS admin_permissions JSONB DEFAULT '{}'::jsonb;

-- Create index for fast staff lookups
CREATE INDEX IF NOT EXISTS idx_users_staff_role ON app.users(staff_role) 
  WHERE staff_role IS NOT NULL;

-- ============================================================================
-- 2. Create audit_logs table
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.audit_logs (
  id                    UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id         UUID              NOT NULL REFERENCES app.users(id),
  action                TEXT              NOT NULL,
  resource_type         TEXT              NOT NULL, -- 'household', 'user', 'subscription', 'plan', etc.
  resource_id           UUID,
  old_values            JSONB,
  new_values            JSONB,
  description           TEXT,
  ip_address            INET,
  user_agent            TEXT,
  created_at            TIMESTAMPTZ       NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE app.audit_logs ENABLE ROW LEVEL SECURITY;

-- Create deny-all policy (Edge Functions use service role)
CREATE POLICY "deny_direct_access"
ON app.audit_logs
FOR ALL
TO anon, authenticated
USING (false);

-- Create indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_audit_logs_admin_user_id ON app.audit_logs(admin_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_resource ON app.audit_logs(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON app.audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON app.audit_logs(action);

-- ============================================================================
-- 3. Create feature_flags table (for Phase 4)
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.feature_flags (
  id                    UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
  name                  TEXT              NOT NULL UNIQUE,
  display_name          TEXT              NOT NULL,
  description           TEXT,
  is_enabled            BOOLEAN           NOT NULL DEFAULT false,
  category              TEXT              DEFAULT 'general', -- 'ai', 'finance', 'integration', 'general'
  is_beta               BOOLEAN           DEFAULT false,
  created_at            TIMESTAMPTZ       NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ       NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE app.feature_flags ENABLE ROW LEVEL SECURITY;

-- Create deny-all policy
CREATE POLICY "deny_direct_access"
ON app.feature_flags
FOR ALL
TO anon, authenticated
USING (false);

-- Create index
CREATE INDEX IF NOT EXISTS idx_feature_flags_name ON app.feature_flags(name);

-- ============================================================================
-- 4. Create household_feature_overrides table (for Phase 4)
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.household_feature_overrides (
  id                    UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id          UUID              NOT NULL REFERENCES app.households(id) ON DELETE CASCADE,
  feature_flag_id       UUID              NOT NULL REFERENCES app.feature_flags(id) ON DELETE CASCADE,
  is_enabled            BOOLEAN           NOT NULL,
  reason                TEXT,
  override_by_admin_id  UUID              REFERENCES app.users(id),
  created_at            TIMESTAMPTZ       NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ       NOT NULL DEFAULT now(),
  UNIQUE(household_id, feature_flag_id)
);

-- Enable RLS
ALTER TABLE app.household_feature_overrides ENABLE ROW LEVEL SECURITY;

-- Create deny-all policy
CREATE POLICY "deny_direct_access"
ON app.household_feature_overrides
FOR ALL
TO anon, authenticated
USING (false);

-- Create index
CREATE INDEX IF NOT EXISTS idx_household_feature_overrides_household_id 
  ON app.household_feature_overrides(household_id);

-- ============================================================================
-- 5. Add admin_notes to households (for Phase 2)
-- ============================================================================

ALTER TABLE app.households
  ADD COLUMN IF NOT EXISTS admin_notes TEXT;

ALTER TABLE app.households
  ADD COLUMN IF NOT EXISTS suspension_reason TEXT;

-- ============================================================================
-- 6. Trigger for updated_at on new tables
-- ============================================================================

CREATE TRIGGER handle_feature_flags_updated_at
  BEFORE UPDATE ON app.feature_flags
  FOR EACH ROW
  EXECUTE FUNCTION app.handle_updated_at();

CREATE TRIGGER handle_household_feature_overrides_updated_at
  BEFORE UPDATE ON app.household_feature_overrides
  FOR EACH ROW
  EXECUTE FUNCTION app.handle_updated_at();

-- ============================================================================
-- 7. Insert default feature flags
-- ============================================================================

INSERT INTO app.feature_flags (name, display_name, description, is_enabled, category, is_beta) VALUES
  ('email_ingestion', 'Email Ingestion', 'Allow households to connect email accounts for transaction ingestion', true, 'integration', false),
  ('csv_import', 'CSV Import', 'Allow households to import expenses/budgets from CSV files', true, 'finance', false),
  ('voice_features', 'Voice Features', 'Allow voice-based expense entry and queries', true, 'general', false),
  ('ai_chat', 'AI Chat', 'Enable AI-powered financial insights and chat', true, 'ai', false),
  ('investment_tracking', 'Investment Tracking', 'Enable investment portfolio tracking', true, 'finance', false),
  ('family_planner', 'Family Planner', 'Enable family event planning calendar', true, 'general', false),
  ('savings_goals', 'Savings Goals', 'Enable savings goal tracking', true, 'finance', false)
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- Verification
-- ============================================================================

-- Check new columns added
-- SELECT column_name, data_type FROM information_schema.columns 
-- WHERE table_schema = 'app' AND table_name = 'users' 
-- AND column_name IN ('staff_role', 'staff_scope', 'admin_permissions')
-- ORDER BY ordinal_position;

-- Check new tables exist
-- SELECT table_name FROM information_schema.tables 
-- WHERE table_schema = 'app' 
-- AND table_name IN ('audit_logs', 'feature_flags', 'household_feature_overrides')
-- ORDER BY table_name;
