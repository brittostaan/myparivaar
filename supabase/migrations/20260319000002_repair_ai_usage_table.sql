-- ============================================================================
-- Migration: Repair missing ai_usage table on remote environments
-- Created: 2026-03-19
-- Purpose: Ensure app.ai_usage exists with expected RLS policy and index
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.ai_usage (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id          UUID        NOT NULL REFERENCES app.households(id),
  month                 TEXT        NOT NULL CHECK (month ~ '^\d{4}-\d{2}$'),
  chat_count            INT         NOT NULL DEFAULT 0 CHECK (chat_count >= 0),
  summary_generated_at  TIMESTAMPTZ,
  UNIQUE (household_id, month)
);

ALTER TABLE app.ai_usage ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'app'
      AND tablename = 'ai_usage'
      AND policyname = 'deny_direct_access'
  ) THEN
    CREATE POLICY "deny_direct_access"
    ON app.ai_usage
    FOR ALL
    TO anon, authenticated
    USING (false);
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_ai_usage_household_id ON app.ai_usage(household_id);