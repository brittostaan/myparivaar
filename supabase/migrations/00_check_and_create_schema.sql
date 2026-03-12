-- ========================================
-- STEP 1: Check current database state
-- Run this first to see what exists
-- ========================================

-- Check if app schema exists
SELECT schema_name 
FROM information_schema.schemata 
WHERE schema_name = 'app';

-- Check what tables exist in app schema (if any)
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'app';

-- ========================================
-- STEP 2: Create minimal schema for authentication
-- Run this if the checks above show nothing exists
-- ========================================

-- Create app schema
CREATE SCHEMA IF NOT EXISTS app;

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION app.handle_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

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

-- Create users table with EMAIL column
CREATE TABLE IF NOT EXISTS app.users (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid           TEXT        UNIQUE NOT NULL,
  email                  TEXT,
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

-- Add triggers
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'households_updated_at'
      AND tgrelid = 'app.households'::regclass
  ) THEN
    CREATE TRIGGER households_updated_at
      BEFORE UPDATE ON app.households
      FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'users_updated_at'
      AND tgrelid = 'app.users'::regclass
  ) THEN
    CREATE TRIGGER users_updated_at
      BEFORE UPDATE ON app.users
      FOR EACH ROW EXECUTE FUNCTION app.handle_updated_at();
  END IF;
END;
$$;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_users_firebase_uid ON app.users (firebase_uid);
CREATE INDEX IF NOT EXISTS idx_users_email ON app.users (email);
CREATE INDEX IF NOT EXISTS idx_users_household_id ON app.users (household_id);
CREATE INDEX IF NOT EXISTS idx_households_admin ON app.households (admin_firebase_uid);

-- ========================================
-- STEP 3: Grant permissions
-- ========================================

-- Grant usage on schema
GRANT USAGE ON SCHEMA app TO postgres, anon, authenticated, service_role;

-- Grant permissions on all tables
GRANT ALL ON ALL TABLES IN SCHEMA app TO postgres, service_role;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA app TO authenticated;

-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL ON TABLES TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT, INSERT, UPDATE ON TABLES TO authenticated;
