-- ========================================
-- ALTER existing users table to add email column
-- Run this in Supabase Dashboard → SQL Editor
-- ========================================

-- Add email column to existing users table
ALTER TABLE app.users 
  ADD COLUMN IF NOT EXISTS email TEXT;

-- Create index on email for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_email 
  ON app.users (email);

-- Verify the column was added
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'app' 
  AND table_name = 'users'
ORDER BY ordinal_position;
