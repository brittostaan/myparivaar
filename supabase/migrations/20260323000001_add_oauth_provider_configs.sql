-- OAuth Provider Configuration Table
-- Allows admins to configure Google/Microsoft OAuth credentials via the Admin Center UI.
-- Edge functions (email-connectUrl, email-oauthCallback) read from this table
-- instead of requiring manually-set Supabase secrets.

CREATE TABLE IF NOT EXISTS app.oauth_provider_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider TEXT NOT NULL UNIQUE CHECK (provider IN ('google', 'microsoft')),
  client_id TEXT NOT NULL,
  client_secret TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  redirect_uri TEXT,  -- override if needed; defaults to supabase callback URL
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES app.users(id)
);

ALTER TABLE app.oauth_provider_configs ENABLE ROW LEVEL SECURITY;

-- Only service role can access this table (edge functions use service role key).
-- No direct user access; all management goes through admin edge functions.
CREATE POLICY "Service role full access on oauth_provider_configs"
  ON app.oauth_provider_configs
  FOR ALL
  USING (true)
  WITH CHECK (true);
