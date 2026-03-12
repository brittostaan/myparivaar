-- Create public.transactions table (was previously only in app schema)
-- Edge functions query public schema, so this table must exist in public.

CREATE TABLE IF NOT EXISTS public.transactions (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id          UUID          NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  created_by_user_id    UUID          REFERENCES public.users(id),
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

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_transactions_household_id ON public.transactions(household_id);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON public.transactions(date DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_deleted_at ON public.transactions(deleted_at) WHERE deleted_at IS NULL;

-- Grant permissions
GRANT ALL ON public.transactions TO service_role;
GRANT ALL ON public.transactions TO authenticated;
GRANT ALL ON public.transactions TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
