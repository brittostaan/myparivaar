-- Login history table to track user sign-in events
CREATE TABLE IF NOT EXISTS app.login_history (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  ip_address  TEXT,
  user_agent  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_login_history_user_id ON app.login_history (user_id);
CREATE INDEX idx_login_history_created_at ON app.login_history (created_at DESC);
