-- Migration: Create savings_goals table
-- Created: 2026-03-15
--
-- Schema matches the deployed Edge Functions:
--   savings-list        : queries by household_id, filters deleted_at IS NULL
--   savings-upsert      : insert or update by id
--   savings-delete      : soft-delete by setting deleted_at
--   savings-contribute  : increments current_amount by the given amount

CREATE TABLE IF NOT EXISTS app.savings_goals (
    id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id   UUID          NOT NULL REFERENCES app.households(id) ON DELETE CASCADE,
    name           TEXT          NOT NULL CHECK (char_length(name) >= 1 AND char_length(name) <= 100),
    target_amount  NUMERIC(12,2) NOT NULL CHECK (target_amount > 0),
    current_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (current_amount >= 0),
    target_date    DATE,
    notes          TEXT,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    deleted_at     TIMESTAMPTZ
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS savings_goals_household_id_idx ON app.savings_goals (household_id);

-- Auto-update updated_at on row changes
-- Reuse app.set_updated_at() if it already exists from budgets migration
DROP TRIGGER IF EXISTS savings_goals_set_updated_at ON app.savings_goals;
CREATE TRIGGER savings_goals_set_updated_at
    BEFORE UPDATE ON app.savings_goals
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- Edge Functions use the service role key which bypasses RLS.
-- Enable RLS and deny direct anon/authenticated access for safety.
ALTER TABLE app.savings_goals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deny_direct_access" ON app.savings_goals;
CREATE POLICY "deny_direct_access" ON app.savings_goals
    FOR ALL TO anon, authenticated
    USING (false);
