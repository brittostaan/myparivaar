-- Migration: Create investments table
-- Created: 2026-03-18
--
-- Supports edge functions:
--   investment-list
--   investment-upsert
--   investment-delete

CREATE TABLE IF NOT EXISTS app.investments (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id    UUID          NOT NULL REFERENCES app.households(id) ON DELETE CASCADE,
    created_by      UUID          REFERENCES app.users(id) ON DELETE SET NULL,
    name            TEXT          NOT NULL CHECK (char_length(name) >= 1 AND char_length(name) <= 120),
    type            TEXT          NOT NULL CHECK (char_length(type) >= 1 AND char_length(type) <= 50),
    provider        TEXT,
    amount_invested NUMERIC(14,2) NOT NULL CHECK (amount_invested >= 0),
    current_value   NUMERIC(14,2) NOT NULL CHECK (current_value >= 0),
    due_date        DATE,
    maturity_date   DATE,
    frequency       TEXT          NOT NULL DEFAULT 'One-time',
    risk_level      TEXT          NOT NULL DEFAULT 'medium' CHECK (risk_level IN ('low','medium','high')),
    notes           TEXT,
    child_name      TEXT,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ,
    CONSTRAINT investments_maturity_after_due CHECK (maturity_date IS NULL OR due_date IS NULL OR maturity_date >= due_date)
);

ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS household_id UUID REFERENCES app.households(id) ON DELETE CASCADE;
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES app.users(id) ON DELETE SET NULL;
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS type TEXT;
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS provider TEXT;
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS amount_invested NUMERIC(14,2);
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS current_value NUMERIC(14,2);
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS due_date DATE;
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS maturity_date DATE;
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS frequency TEXT DEFAULT 'One-time';
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS risk_level TEXT DEFAULT 'medium';
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS child_name TEXT;
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE app.investments ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS investments_household_idx
    ON app.investments (household_id, created_at DESC);

CREATE INDEX IF NOT EXISTS investments_child_idx
    ON app.investments (child_name);

CREATE INDEX IF NOT EXISTS investments_status_idx
    ON app.investments (deleted_at);

DROP TRIGGER IF EXISTS investments_set_updated_at ON app.investments;
CREATE TRIGGER investments_set_updated_at
    BEFORE UPDATE ON app.investments
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

ALTER TABLE app.investments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deny_direct_access" ON app.investments;
CREATE POLICY "deny_direct_access" ON app.investments
    FOR ALL TO anon, authenticated
    USING (false);
