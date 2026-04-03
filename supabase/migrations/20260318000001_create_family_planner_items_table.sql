-- Migration: Create family planner items table
-- Created: 2026-03-18
--
-- Supports edge functions:
--   family-planner-list
--   family-planner-upsert
--   family-planner-delete
--   family-planner-status

CREATE TABLE IF NOT EXISTS app.family_planner_items (
    id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id        UUID          NOT NULL REFERENCES app.households(id) ON DELETE CASCADE,
    created_by          UUID          REFERENCES app.users(id) ON DELETE SET NULL,
    item_type           TEXT          NOT NULL CHECK (item_type IN ('birthday','anniversary','vacation','event','reminder','task')),
    title               TEXT          NOT NULL CHECK (char_length(title) >= 1 AND char_length(title) <= 120),
    description         TEXT,
    start_date          DATE          NOT NULL,
    end_date            DATE,
    is_all_day          BOOLEAN       NOT NULL DEFAULT true,
    is_completed        BOOLEAN       NOT NULL DEFAULT false,
    completed_at        TIMESTAMPTZ,
    is_recurring_yearly BOOLEAN      NOT NULL DEFAULT false,
    priority            TEXT          NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high')),
    location            TEXT,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,
    CONSTRAINT family_planner_end_after_start CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS family_planner_household_idx
    ON app.family_planner_items (household_id, start_date);

CREATE INDEX IF NOT EXISTS family_planner_status_idx
    ON app.family_planner_items (is_completed, deleted_at);

CREATE INDEX IF NOT EXISTS family_planner_type_idx
    ON app.family_planner_items (item_type);

DROP TRIGGER IF EXISTS family_planner_items_set_updated_at ON app.family_planner_items;
CREATE TRIGGER family_planner_items_set_updated_at
    BEFORE UPDATE ON app.family_planner_items
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

ALTER TABLE app.family_planner_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deny_direct_access" ON app.family_planner_items;
CREATE POLICY "deny_direct_access" ON app.family_planner_items
    FOR ALL TO anon, authenticated
    USING (false);
