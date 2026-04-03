-- Create email_accounts table if it was not already created by a prior migration
-- (guard against silent migration failures on live DB).
CREATE TABLE IF NOT EXISTS public.email_accounts (
  id                         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id               UUID        NOT NULL REFERENCES app.households(id) ON DELETE CASCADE,
  user_id                    UUID        NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  email_address              TEXT        NOT NULL,
  provider                   TEXT        NOT NULL CHECK (provider IN ('gmail', 'outlook')),
  is_active                  BOOLEAN     NOT NULL DEFAULT true,
  access_token               TEXT,
  refresh_token              TEXT,
  token_expires_at           TIMESTAMPTZ,
  last_synced_at             TIMESTAMPTZ,
  screening_sender_filters   TEXT[]      NOT NULL DEFAULT '{}',
  screening_keyword_filters  TEXT[]      NOT NULL DEFAULT '{}',
  screening_scope_unit       TEXT        NOT NULL DEFAULT 'days'
                               CHECK (screening_scope_unit IN ('days', 'months')),
  screening_scope_value      INTEGER     NOT NULL DEFAULT 7
                               CHECK (screening_scope_value BETWEEN 1 AND 365),
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(household_id, email_address)
);

-- Add screening columns if the table already existed without them
ALTER TABLE public.email_accounts
  ADD COLUMN IF NOT EXISTS screening_sender_filters  TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS screening_keyword_filters TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS screening_scope_unit      TEXT   NOT NULL DEFAULT 'days',
  ADD COLUMN IF NOT EXISTS screening_scope_value     INTEGER NOT NULL DEFAULT 7;

-- Ensure constraints exist (idempotent)
ALTER TABLE public.email_accounts
  DROP CONSTRAINT IF EXISTS email_accounts_screening_scope_unit_check,
  ADD CONSTRAINT email_accounts_screening_scope_unit_check
    CHECK (screening_scope_unit IN ('days', 'months'));

ALTER TABLE public.email_accounts
  DROP CONSTRAINT IF EXISTS email_accounts_screening_scope_value_check,
  ADD CONSTRAINT email_accounts_screening_scope_value_check
    CHECK (screening_scope_value BETWEEN 1 AND 365);

-- Grants (safe to re-run)
GRANT ALL ON public.email_accounts TO service_role;
GRANT ALL ON public.email_accounts TO authenticated;

CREATE INDEX IF NOT EXISTS idx_email_accounts_household_id
  ON public.email_accounts(household_id);
CREATE INDEX IF NOT EXISTS idx_email_accounts_user_id
  ON public.email_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_email_accounts_provider_active
  ON public.email_accounts(provider, is_active);
