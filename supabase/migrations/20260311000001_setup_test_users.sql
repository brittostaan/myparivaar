-- ============================================================================
-- Migration: Setup Test Users for Development
-- Created: 2026-03-11
-- Purpose: Create household and test users for Supabase authentication
-- ============================================================================

-- NOTE: Before running this migration:
-- 1. Create users in Supabase Dashboard → Authentication → Users:
--    - britto@myparivaar.com / Britto123
--    - devi@myparivaar.com / Devi123
--    - kevin@myparivaar.com / Kevin123
--    - riya@myparivaar.com / Riya123
-- 2. Copy their Supabase user IDs from the dashboard
-- 3. Replace the placeholder UUIDs below with actual user IDs

-- ============================================================================
-- Create Test Household
-- ============================================================================

-- Insert household with Devi as admin (use Devi's Supabase auth UID)
INSERT INTO app.households (id, name, admin_firebase_uid, plan, suspended, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000001'::uuid,
  'Devi''s Family',
  '9eefa45c-71b3-4238-ad47-3af7769ff328',  -- Devi's Supabase UID
  'free',
  false,
  now(),
  now()
)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- Create Test Users in app.users table
-- ============================================================================

-- Super Admin User: britto
-- Role: super_admin (platform-wide access, not linked to household)
INSERT INTO app.users (
  id,
  firebase_uid,
  phone,
  household_id,
  role,
  display_name,
  notifications_enabled,
  voice_enabled,
  created_at,
  updated_at
)
VALUES (
  gen_random_uuid(),
  '9deb605d-d67a-4b12-bb64-c87c524e5067',  -- Britto's Supabase UID
  '+91-0000000001',  -- Placeholder phone for testing
  NULL,  -- Super admin not linked to household
  'super_admin',
  'Britto',
  true,
  true,
  now(),
  now()
)
ON CONFLICT (firebase_uid) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  role = EXCLUDED.role;

-- Family Head User: devi
-- Role: admin (can manage family members, linked to Devi's Family)
INSERT INTO app.users (
  id,
  firebase_uid,
  phone,
  household_id,
  role,
  display_name,
  notifications_enabled,
  voice_enabled,
  created_at,
  updated_at
)
VALUES (
  gen_random_uuid(),
  '9eefa45c-71b3-4238-ad47-3af7769ff328',  -- Devi's Supabase UID
  '+91-0000000002',  -- Placeholder phone for testing
  '00000000-0000-0000-0000-000000000001'::uuid,
  'admin',
  'Devi',
  true,
  true,
  now(),
  now()
)
ON CONFLICT (firebase_uid) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  household_id = EXCLUDED.household_id,
  role = EXCLUDED.role;

-- Family Member User: kevin
-- Role: member (can view and add expenses, linked to Devi's Family)
INSERT INTO app.users (
  id,
  firebase_uid,
  phone,
  household_id,
  role,
  display_name,
  notifications_enabled,
  voice_enabled,
  created_at,
  updated_at
)
VALUES (
  gen_random_uuid(),
  '24e1a20d-98b4-45b9-adeb-064af7fa9507',  -- Kevin's Supabase UID
  '+91-0000000003',  -- Placeholder phone for testing
  '00000000-0000-0000-0000-000000000001'::uuid,
  'member',
  'Kevin',
  true,
  true,
  now(),
  now()
)
ON CONFLICT (firebase_uid) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  household_id = EXCLUDED.household_id;

-- Family Member User: riya
-- Role: member (can view and add expenses, linked to Devi's Family)
INSERT INTO app.users (
  id,
  firebase_uid,
  phone,
  household_id,
  role,
  display_name,
  notifications_enabled,
  voice_enabled,
  created_at,
  updated_at
)
VALUES (
  gen_random_uuid(),
  'ddd906ad-e1c1-4c66-8c7b-2b56d995dadd',  -- Riya's Supabase UID
  '+91-0000000004',  -- Placeholder phone for testing
  '00000000-0000-0000-0000-000000000001'::uuid,
  'member',
  'Riya',
  true,
  true,
  now(),
  now()
)
ON CONFLICT (firebase_uid) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  household_id = EXCLUDED.household_id;

-- ============================================================================
-- Verification Queries
-- ============================================================================

-- Run these after migration to verify setup:

-- Check household
-- SELECT * FROM app.households WHERE id = '00000000-0000-0000-0000-000000000001';

-- Check all test users
-- SELECT 
--   display_name,
--   role,
--   phone,
--   household_id,
--   firebase_uid
-- FROM app.users
-- WHERE display_name IN ('Britto', 'Devi', 'Kevin', 'Riya')
-- ORDER BY role DESC, display_name;

-- ============================================================================
-- INSTRUCTIONS FOR DEPLOYMENT:
-- ============================================================================
-- 1. Go to Supabase Dashboard → Authentication → Users → Add user
-- 2. Create each user with email and password:
--    - britto@myparivaar.com / Britto123
--    - devi@myparivaar.com / Devi123
--    - kevin@myparivaar.com / Kevin123
--    - riya@myparivaar.com / Riya123
-- 3. Disable email confirmation for test users (optional)
-- 4. Copy each user's UUID from the dashboard
-- 5. Replace all REPLACE_WITH_*_SUPABASE_UID placeholders in this file
-- 6. Run: supabase db push OR manually run this SQL in SQL Editor
-- ============================================================================
