-- Add profile columns to app.users that are expected by the app but missing from DB
ALTER TABLE app.users ADD COLUMN IF NOT EXISTS first_name TEXT;
ALTER TABLE app.users ADD COLUMN IF NOT EXISTS last_name TEXT;
ALTER TABLE app.users ADD COLUMN IF NOT EXISTS date_of_birth DATE;
ALTER TABLE app.users ADD COLUMN IF NOT EXISTS photo_url TEXT;
