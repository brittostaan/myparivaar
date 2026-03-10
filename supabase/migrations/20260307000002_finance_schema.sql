-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: finance schema
-- Covers: import_batches, household_invites, transactions, budgets,
--         savings_goals, savings_contributions, bills, user_settings
-- All tables live in the app schema.
-- Safe to run on a database where migration 1 has already been applied.
-- Uses IF NOT EXISTS patterns throughout; DO blocks guard triggers and policies.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────
-- Ensure schema exists (idempotent)
-- ─────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS app;

-- ─────────────────────────────────────────
-- Bridge: add is_active to app.users
-- (Migration 1 used deleted_at only; Edge Functions expect is_active)
-- ─────────────────────────────────────────
ALTER TABLE app.users
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- Back-fill: any rows with deleted_at set should be inactive
UPDATE app.users SET is_active = false WHERE deleted_at IS NOT NULL AND is_active = true;

-- ─────────────────────────────────────────
-- import_batches
-- Created first — transactions and budgets reference it.
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app.import_batches (
  id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id          UUID         NOT NULL REFERENCES app.households(id),
  imported_by_user_id   UUID         NOT NULL REFERENCES app.users(id),
  type                  TEXT         NOT NULL CHECK (type IN ('expenses', 'budgets')),
  row_count             INT          NOT NULL CHECK (row_count > 0),
  status                TEXT         NOT NULL DEFAULT 'completed'
                                     CHECK (status IN ('completed', 'failed')),
  created_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ  NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'import_batches_updated_at'
      AND tgrelid = 'app.import_batches'::regclass
  ) THEN
    CREATE TRIGGER import_batches_updated_at
      BEFORE UPDATE ON app.import_batches
      FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();
  END IF;
END;
$$;

-- ─────────────────────────────────────────
-- household_invites
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app.household_invites (
  id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id          UUID         NOT NULL REFERENCES app.households(id),
  invited_by_user_id    UUID         NOT NULL REFERENCES app.users(id),
  phone                 TEXT         NOT NULL,
  code                  TEXT         NOT NULL UNIQUE,
  status                TEXT         NOT NULL DEFAULT 'pending'
                                     CHECK (status IN ('pending', 'accepted', 'revoked', 'expired')),
  expires_at            TIMESTAMPTZ  NOT NULL,
  created_at            TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────
-- transactions  (user-facing concept: "expenses")
-- source tracks entry channel; status for admin review workflow
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app.transactions (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id          UUID          NOT NULL REFERENCES app.households(id),
  created_by_user_id    UUID          REFERENCES app.users(id),
  imported_by_user_id   UUID          REFERENCES app.users(id),
  import_batch_id       UUID          REFERENCES app.import_batches(id),
  date                  DATE          NOT NULL,
  amount                NUMERIC(12,2) NOT NULL CHECK (amount > 0 AND amount <= 99999999.99),
  category              TEXT          NOT NULL CHECK (char_length(trim(category)) BETWEEN 1 AND 50),
  description           TEXT          NOT NULL CHECK (char_length(trim(description)) BETWEEN 1 AND 200),
  notes                 TEXT          CHECK (char_length(notes) <= 500),
  source                TEXT          NOT NULL DEFAULT 'manual'
                                      CHECK (source IN ('manual', 'csv', 'email')),
  status                TEXT          NOT NULL DEFAULT 'approved'
                                      CHECK (status IN ('pending', 'approved', 'rejected')),
  deleted_at            TIMESTAMPTZ,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'transactions_updated_at'
      AND tgrelid = 'app.transactions'::regclass
  ) THEN
    CREATE TRIGGER transactions_updated_at
      BEFORE UPDATE ON app.transactions
      FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();
  END IF;
END;
$$;

-- ─────────────────────────────────────────
-- budgets
-- Unique on (household_id, category, month) — upsert conflict target
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app.budgets (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id          UUID          NOT NULL REFERENCES app.households(id),
  imported_by_user_id   UUID          REFERENCES app.users(id),
  import_batch_id       UUID          REFERENCES app.import_batches(id),
  category              TEXT          NOT NULL CHECK (char_length(trim(category)) BETWEEN 1 AND 50),
  amount                NUMERIC(12,2) NOT NULL CHECK (amount > 0 AND amount <= 99999999.99),
  month                 TEXT          NOT NULL CHECK (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  deleted_at            TIMESTAMPTZ,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
  UNIQUE (household_id, category, month)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'budgets_updated_at'
      AND tgrelid = 'app.budgets'::regclass
  ) THEN
    CREATE TRIGGER budgets_updated_at
      BEFORE UPDATE ON app.budgets
      FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();
  END IF;
END;
$$;

-- ─────────────────────────────────────────
-- savings_goals
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app.savings_goals (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id          UUID          NOT NULL REFERENCES app.households(id),
  created_by_user_id    UUID          REFERENCES app.users(id),
  name                  TEXT          NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 100),
  target_amount         NUMERIC(12,2) NOT NULL CHECK (target_amount > 0),
  current_amount        NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (current_amount >= 0),
  target_date           DATE,
  status                TEXT          NOT NULL DEFAULT 'active'
                                      CHECK (status IN ('active', 'achieved', 'cancelled')),
  deleted_at            TIMESTAMPTZ,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'savings_goals_updated_at'
      AND tgrelid = 'app.savings_goals'::regclass
  ) THEN
    CREATE TRIGGER savings_goals_updated_at
      BEFORE UPDATE ON app.savings_goals
      FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();
  END IF;
END;
$$;

-- ─────────────────────────────────────────
-- savings_contributions
-- Each row is a deposit toward a goal.
-- current_amount on savings_goals is denormalised; update it via trigger below.
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app.savings_contributions (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  savings_goal_id       UUID          NOT NULL REFERENCES app.savings_goals(id),
  household_id          UUID          NOT NULL REFERENCES app.households(id),
  contributed_by_user_id UUID         REFERENCES app.users(id),
  amount                NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  date                  DATE          NOT NULL,
  note                  TEXT          CHECK (char_length(note) <= 300),
  deleted_at            TIMESTAMPTZ,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'savings_contributions_updated_at'
      AND tgrelid = 'app.savings_contributions'::regclass
  ) THEN
    CREATE TRIGGER savings_contributions_updated_at
      BEFORE UPDATE ON app.savings_contributions
      FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();
  END IF;
END;
$$;

-- Trigger: keep savings_goals.current_amount in sync after insert/update/delete
CREATE OR REPLACE FUNCTION app.sync_savings_current_amount()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_goal_id UUID;
BEGIN
  -- Determine which goal_id changed
  IF TG_OP = 'DELETE' THEN
    v_goal_id := OLD.savings_goal_id;
  ELSE
    v_goal_id := NEW.savings_goal_id;
  END IF;

  UPDATE app.savings_goals
  SET current_amount = COALESCE((
    SELECT SUM(amount)
    FROM   app.savings_contributions
    WHERE  savings_goal_id = v_goal_id
      AND  deleted_at IS NULL
  ), 0)
  WHERE id = v_goal_id;

  RETURN NULL; -- AFTER trigger, return value is ignored
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'savings_contributions_sync_goal'
      AND tgrelid = 'app.savings_contributions'::regclass
  ) THEN
    CREATE TRIGGER savings_contributions_sync_goal
      AFTER INSERT OR UPDATE OR DELETE ON app.savings_contributions
      FOR EACH ROW EXECUTE FUNCTION app.sync_savings_current_amount();
  END IF;
END;
$$;

-- ─────────────────────────────────────────
-- bills
-- Recurring or one-time payment obligations tracked per household
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app.bills (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id          UUID          NOT NULL REFERENCES app.households(id),
  created_by_user_id    UUID          REFERENCES app.users(id),
  name                  TEXT          NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 100),
  category              TEXT          NOT NULL CHECK (char_length(trim(category)) BETWEEN 1 AND 50),
  amount                NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  frequency             TEXT          NOT NULL DEFAULT 'monthly'
                                      CHECK (frequency IN ('monthly', 'quarterly', 'yearly', 'one_time')),
  due_day               SMALLINT      CHECK (due_day BETWEEN 1 AND 31),
  next_due_date         DATE,
  auto_pay              BOOLEAN       NOT NULL DEFAULT false,
  status                TEXT          NOT NULL DEFAULT 'active'
                                      CHECK (status IN ('active', 'cancelled')),
  deleted_at            TIMESTAMPTZ,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'bills_updated_at'
      AND tgrelid = 'app.bills'::regclass
  ) THEN
    CREATE TRIGGER bills_updated_at
      BEFORE UPDATE ON app.bills
      FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();
  END IF;
END;
$$;

-- ─────────────────────────────────────────
-- user_settings
-- One row per user. For preferences not covered by app.users columns.
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app.user_settings (
  id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID         NOT NULL UNIQUE REFERENCES app.users(id),
  currency              TEXT         NOT NULL DEFAULT 'INR'
                                     CHECK (char_length(currency) = 3),
  language              TEXT         NOT NULL DEFAULT 'en'
                                     CHECK (char_length(language) BETWEEN 2 AND 5),
  created_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ  NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'user_settings_updated_at'
      AND tgrelid = 'app.user_settings'::regclass
  ) THEN
    CREATE TRIGGER user_settings_updated_at
      BEFORE UPDATE ON app.user_settings
      FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();
  END IF;
END;
$$;

-- ─────────────────────────────────────────
-- Row Level Security (deny-by-default)
-- Edge Functions use service_role which bypasses RLS.
-- Applied with ALTER TABLE (idempotent) + DO blocks for policies.
-- ─────────────────────────────────────────
ALTER TABLE app.import_batches       ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.household_invites    ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.transactions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.budgets              ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.savings_goals        ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.savings_contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.bills                ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.user_settings        ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'import_batches', 'household_invites', 'transactions', 'budgets',
    'savings_goals', 'savings_contributions', 'bills', 'user_settings'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'app'
        AND tablename  = tbl
        AND policyname = 'deny_direct_access'
    ) THEN
      EXECUTE format(
        'CREATE POLICY "deny_direct_access" ON app.%I FOR ALL TO anon, authenticated USING (false)',
        tbl
      );
    END IF;
  END LOOP;
END;
$$;

-- ─────────────────────────────────────────
-- Indexes
-- ─────────────────────────────────────────

-- import_batches
CREATE INDEX IF NOT EXISTS idx_import_batches_household_id
  ON app.import_batches (household_id);

-- household_invites
CREATE INDEX IF NOT EXISTS idx_household_invites_household_id
  ON app.household_invites (household_id);
CREATE INDEX IF NOT EXISTS idx_household_invites_code
  ON app.household_invites (code);
CREATE INDEX IF NOT EXISTS idx_household_invites_phone
  ON app.household_invites (phone);

-- transactions
CREATE INDEX IF NOT EXISTS idx_transactions_household_id
  ON app.transactions (household_id);
CREATE INDEX IF NOT EXISTS idx_transactions_household_date
  ON app.transactions (household_id, date DESC)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_transactions_import_batch_id
  ON app.transactions (import_batch_id)
  WHERE import_batch_id IS NOT NULL;

-- budgets
CREATE INDEX IF NOT EXISTS idx_budgets_household_month
  ON app.budgets (household_id, month)
  WHERE deleted_at IS NULL;

-- savings_goals
CREATE INDEX IF NOT EXISTS idx_savings_goals_household_id
  ON app.savings_goals (household_id)
  WHERE deleted_at IS NULL;

-- savings_contributions
CREATE INDEX IF NOT EXISTS idx_savings_contributions_goal_id
  ON app.savings_contributions (savings_goal_id)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_savings_contributions_household_id
  ON app.savings_contributions (household_id)
  WHERE deleted_at IS NULL;

-- bills
CREATE INDEX IF NOT EXISTS idx_bills_household_id
  ON app.bills (household_id)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_bills_next_due_date
  ON app.bills (household_id, next_due_date)
  WHERE deleted_at IS NULL AND status = 'active';

-- user_settings
CREATE INDEX IF NOT EXISTS idx_user_settings_user_id
  ON app.user_settings (user_id);
