-- Migration: Create bills table
-- Created: 2026-03-17
--
-- Supports edge functions:
--   bills-list
--   bills-upsert
--   bills-delete
--   bills-mark-paid

CREATE TABLE IF NOT EXISTS app.bills (
    id           UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID           NOT NULL REFERENCES app.households(id) ON DELETE CASCADE,
    name         TEXT           NOT NULL CHECK (char_length(name) >= 1 AND char_length(name) <= 100),
    provider     TEXT,
    category     TEXT           NOT NULL CHECK (category IN ('rent','utilities','internet','insurance','credit_card','subscription','loan','school','other')),
    frequency    TEXT           NOT NULL CHECK (frequency IN ('monthly','quarterly','yearly','one_time')),
    amount       NUMERIC(12,2)  NOT NULL CHECK (amount > 0),
    due_date     DATE           NOT NULL,
    is_recurring BOOLEAN        NOT NULL DEFAULT true,
    is_paid      BOOLEAN        NOT NULL DEFAULT false,
    paid_on      TIMESTAMPTZ,
    notes        TEXT,
    created_at   TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ    NOT NULL DEFAULT now(),
    deleted_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS bills_household_id_idx ON app.bills (household_id);
CREATE INDEX IF NOT EXISTS bills_due_date_idx ON app.bills (due_date);
CREATE INDEX IF NOT EXISTS bills_status_idx ON app.bills (is_paid, deleted_at);

DROP TRIGGER IF EXISTS bills_set_updated_at ON app.bills;
CREATE TRIGGER bills_set_updated_at
    BEFORE UPDATE ON app.bills
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

ALTER TABLE app.bills ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deny_direct_access" ON app.bills;
CREATE POLICY "deny_direct_access" ON app.bills
    FOR ALL TO anon, authenticated
    USING (false);
