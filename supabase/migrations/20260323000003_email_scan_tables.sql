-- Create tables for email inbox scanning feature:
-- 1. email_scan_results  – tracks each scan run (status, progress, results)
-- 2. email_scanned_emails – tracks individual emails processed (dedup)

CREATE TABLE IF NOT EXISTS public.email_scan_results (
  id                     UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  email_account_id       UUID          NOT NULL REFERENCES public.email_accounts(id) ON DELETE CASCADE,
  status                 TEXT          NOT NULL DEFAULT 'scanning' CHECK (status IN ('scanning', 'completed', 'failed')),
  folders_scanned        JSONB         NOT NULL DEFAULT '[]'::jsonb,
  total_emails_scanned   INT           NOT NULL DEFAULT 0,
  total_transactions_found INT         NOT NULL DEFAULT 0,
  use_ai                 BOOLEAN       NOT NULL DEFAULT false,
  error_message          TEXT,
  scan_started_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
  scan_completed_at      TIMESTAMPTZ,
  created_at             TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_email_scan_results_account
  ON public.email_scan_results(email_account_id);
CREATE INDEX IF NOT EXISTS idx_email_scan_results_status
  ON public.email_scan_results(status) WHERE status = 'scanning';

CREATE TABLE IF NOT EXISTS public.email_scanned_emails (
  id                     UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  email_account_id       UUID          NOT NULL REFERENCES public.email_accounts(id) ON DELETE CASCADE,
  scan_result_id         UUID          REFERENCES public.email_scan_results(id) ON DELETE SET NULL,
  provider_message_id    TEXT          NOT NULL,
  subject                TEXT,
  sender                 TEXT,
  received_at            TIMESTAMPTZ,
  folder_name            TEXT,
  has_transaction        BOOLEAN       NOT NULL DEFAULT false,
  transaction_id         UUID,
  ai_classified          BOOLEAN       NOT NULL DEFAULT false,
  created_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),
  UNIQUE(email_account_id, provider_message_id)
);

CREATE INDEX IF NOT EXISTS idx_email_scanned_emails_account
  ON public.email_scanned_emails(email_account_id);
CREATE INDEX IF NOT EXISTS idx_email_scanned_emails_has_tx
  ON public.email_scanned_emails(has_transaction) WHERE has_transaction = true;

-- Grant access to service_role (edge functions use service role key)
GRANT ALL ON public.email_scan_results TO service_role;
GRANT ALL ON public.email_scan_results TO authenticated;
GRANT ALL ON public.email_scanned_emails TO service_role;
GRANT ALL ON public.email_scanned_emails TO authenticated;
