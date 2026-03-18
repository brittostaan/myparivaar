-- Migration: Add tags to finance records
-- Created: 2026-03-18
--
-- Adds user-defined tags for transactions, budgets, and bills.

ALTER TABLE app.transactions
    ADD COLUMN IF NOT EXISTS tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

ALTER TABLE app.budgets
    ADD COLUMN IF NOT EXISTS tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

ALTER TABLE app.bills
    ADD COLUMN IF NOT EXISTS tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

CREATE INDEX IF NOT EXISTS transactions_tags_idx
    ON app.transactions USING GIN (tags);

CREATE INDEX IF NOT EXISTS budgets_tags_idx
    ON app.budgets USING GIN (tags);

CREATE INDEX IF NOT EXISTS bills_tags_idx
    ON app.bills USING GIN (tags);
