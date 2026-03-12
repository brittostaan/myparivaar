-- Add email column to users table
-- Run this in Supabase Dashboard → SQL Editor

-- Add email column if it doesn't exist
ALTER TABLE app.users 
  ADD COLUMN IF NOT EXISTS email TEXT;

-- Create index on email for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_email 
  ON app.users (email);

-- Optional: Copy phone data to email if needed (only for existing rows with phone but no email)
UPDATE app.users 
SET email = phone 
WHERE email IS NULL AND phone IS NOT NULL;

-- Note: phone column is kept for backward compatibility with household invites
-- Future iterations can migrate invite system to use email
