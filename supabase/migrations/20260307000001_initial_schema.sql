-- Migration: initial schema
-- Covers: users, households, ai_usage
-- All tables live in the app schema.
-- RLS enabled, direct access blocked (Edge Functions use service role).

-- ─────────────────────────────────────────
-- Schema
-- ─────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS app;

-- ─────────────────────────────────────────
-- Households
-- ─────────────────────────────────────────
CREATE TABLE app.households (
  id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name               TEXT        NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 50),
  admin_firebase_uid TEXT        NOT NULL,
  plan               TEXT        NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'paid')),
  suspended          BOOLEAN     NOT NULL DEFAULT false,
  deleted_at         TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────
-- Users
-- ─────────────────────────────────────────
CREATE TABLE app.users (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid           TEXT        UNIQUE NOT NULL,
  phone                  TEXT        UNIQUE NOT NULL,
  household_id           UUID        REFERENCES app.households(id),
  role                   TEXT        NOT NULL DEFAULT 'member'
                                     CHECK (role IN ('admin', 'member', 'super_admin')),
  display_name           TEXT        CHECK (char_length(display_name) <= 50),
  notifications_enabled  BOOLEAN     NOT NULL DEFAULT true,
  voice_enabled          BOOLEAN     NOT NULL DEFAULT true,
  deleted_at             TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────
-- AI usage quotas (per household per month)
-- ─────────────────────────────────────────
CREATE TABLE app.ai_usage (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id          UUID        NOT NULL REFERENCES app.households(id),
  month                 TEXT        NOT NULL CHECK (month ~ '^\d{4}-\d{2}$'),  -- YYYY-MM
  chat_count            INT         NOT NULL DEFAULT 0 CHECK (chat_count >= 0),
  summary_generated_at  TIMESTAMPTZ,
  UNIQUE (household_id, month)
);

-- ─────────────────────────────────────────
-- updated_at trigger
-- ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION app.handle_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER households_updated_at
  BEFORE UPDATE ON app.households
  FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();

CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON app.users
  FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();

-- ─────────────────────────────────────────
-- Row Level Security
-- Block all direct client access.
-- Edge Functions use service_role key which bypasses RLS.
-- ─────────────────────────────────────────
ALTER TABLE app.households ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.users      ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.ai_usage   ENABLE ROW LEVEL SECURITY;

-- Deny all access to anon and authenticated roles
CREATE POLICY "deny_direct_access" ON app.households
  FOR ALL TO anon, authenticated USING (false);

CREATE POLICY "deny_direct_access" ON app.users
  FOR ALL TO anon, authenticated USING (false);

CREATE POLICY "deny_direct_access" ON app.ai_usage
  FOR ALL TO anon, authenticated USING (false);

-- ─────────────────────────────────────────
-- Indexes
-- ─────────────────────────────────────────
CREATE INDEX idx_users_firebase_uid    ON app.users (firebase_uid);
CREATE INDEX idx_users_household_id    ON app.users (household_id);
CREATE INDEX idx_ai_usage_household_id ON app.ai_usage (household_id);
