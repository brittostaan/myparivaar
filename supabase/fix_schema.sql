-- Fix: Create app schema and basic tables if they don't exist
-- Run this in Supabase Dashboard → SQL Editor

-- Create app schema
CREATE SCHEMA IF NOT EXISTS app;

-- Create households table
CREATE TABLE IF NOT EXISTS app.households (
  id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name               TEXT        NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 50),
  admin_firebase_uid TEXT        NOT NULL,
  plan               TEXT        NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'paid')),
  suspended          BOOLEAN     NOT NULL DEFAULT false,
  deleted_at         TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create users table
CREATE TABLE IF NOT EXISTS app.users (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid           TEXT        UNIQUE NOT NULL,
  phone                  TEXT,
  household_id           UUID        REFERENCES app.households(id),
  role                   TEXT        NOT NULL DEFAULT 'member'
                                     CHECK (role IN ('admin', 'member', 'super_admin')),
  display_name           TEXT        CHECK (char_length(display_name) <= 50),
  notifications_enabled  BOOLEAN     NOT NULL DEFAULT true,
  voice_enabled          BOOLEAN     NOT NULL DEFAULT true,
  is_active              BOOLEAN     NOT NULL DEFAULT true,
  deleted_at             TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create ai_usage table
CREATE TABLE IF NOT EXISTS app.ai_usage (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id          UUID        NOT NULL REFERENCES app.households(id),
  month                 TEXT        NOT NULL CHECK (month ~ '^\d{4}-\d{2}$'),
  chat_count            INT         NOT NULL DEFAULT 0 CHECK (chat_count >= 0),
  summary_generated_at  TIMESTAMPTZ,
  UNIQUE (household_id, month)
);

-- Create updated_at trigger function if it doesn't exist
CREATE OR REPLACE FUNCTION app.handle_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Add triggers if they don't exist
DROP TRIGGER IF EXISTS households_updated_at ON app.households;
CREATE TRIGGER households_updated_at
  BEFORE UPDATE ON app.households
  FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();

DROP TRIGGER IF EXISTS users_updated_at ON app.users;
CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON app.users
  FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();

-- Enable RLS
ALTER TABLE app.households ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.users      ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.ai_usage   ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "deny_direct_access" ON app.households;
DROP POLICY IF EXISTS "deny_direct_access" ON app.users;
DROP POLICY IF EXISTS "deny_direct_access" ON app.ai_usage;

-- Create deny-all policies
CREATE POLICY "deny_direct_access" ON app.households
  FOR ALL TO anon, authenticated USING (false);

CREATE POLICY "deny_direct_access" ON app.users
  FOR ALL TO anon, authenticated USING (false);

CREATE POLICY "deny_direct_access" ON app.ai_usage
  FOR ALL TO anon, authenticated USING (false);

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_users_firebase_uid ON app.users (firebase_uid);
CREATE INDEX IF NOT EXISTS idx_users_household_id ON app.users (household_id);
CREATE INDEX IF NOT EXISTS idx_ai_usage_household_id ON app.ai_usage (household_id);

-- Verify schema was created
SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'app';

-- Verify tables were created
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'app' AND table_type = 'BASE TABLE'
ORDER BY table_name;
