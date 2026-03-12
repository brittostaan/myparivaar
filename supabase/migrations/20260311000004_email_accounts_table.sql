-- Create public.email_accounts table for storing connected email integrations
CREATE TABLE IF NOT EXISTS public.email_accounts (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id    UUID          NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  user_id         UUID          NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  email_address   TEXT          NOT NULL,
  provider        TEXT          NOT NULL CHECK (provider IN ('gmail', 'outlook')),
  is_active       BOOLEAN       NOT NULL DEFAULT true,
  access_token    TEXT,
  refresh_token   TEXT,
  token_expires_at TIMESTAMPTZ,
  last_synced_at  TIMESTAMPTZ,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
  UNIQUE(household_id, email_address)
);

CREATE INDEX IF NOT EXISTS idx_email_accounts_household_id ON public.email_accounts(household_id);
CREATE INDEX IF NOT EXISTS idx_email_accounts_user_id ON public.email_accounts(user_id);

GRANT ALL ON public.email_accounts TO service_role;
GRANT ALL ON public.email_accounts TO authenticated;
