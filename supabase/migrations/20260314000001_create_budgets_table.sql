-- Migration: Create budgets table
-- Created: 2026-03-14
--
-- Schema matches the deployed Edge Functions:
--   budget-list   : queries by household_id + month, filters deleted_at IS NULL
--   budget-upsert : upserts on conflict (household_id, category, month)
--   budget-delete : soft-deletes by setting deleted_at

CREATE TABLE IF NOT EXISTS app.budgets (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID         NOT NULL REFERENCES app.households(id) ON DELETE CASCADE,
    category     TEXT         NOT NULL,
    amount       NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    -- month stored as YYYY-MM text to match Edge Function contract
    month        TEXT         NOT NULL CHECK (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at   TIMESTAMPTZ,

    -- Enforces one budget per category per month per household.
    -- Required by budget-upsert onConflict: 'household_id,category,month'
    CONSTRAINT budgets_household_category_month_key
        UNIQUE (household_id, category, month)
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS budgets_household_id_idx ON app.budgets (household_id);
CREATE INDEX IF NOT EXISTS budgets_month_idx         ON app.budgets (month);

-- Auto-update updated_at on row changes
CREATE OR REPLACE FUNCTION app.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS budgets_set_updated_at ON app.budgets;
CREATE TRIGGER budgets_set_updated_at
    BEFORE UPDATE ON app.budgets
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- Edge Functions use the service role key which bypasses RLS.
-- Enable RLS and deny direct anon/authenticated access for safety.
ALTER TABLE app.budgets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deny_direct_access" ON app.budgets;
CREATE POLICY "deny_direct_access" ON app.budgets
    FOR ALL TO anon, authenticated
    USING (false);
