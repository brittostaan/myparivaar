-- Move all tables from app schema to public schema
-- Run this in Supabase Dashboard SQL Editor

-- Move households table
ALTER TABLE IF EXISTS app.households SET SCHEMA public;

-- Move users table
ALTER TABLE IF EXISTS app.users SET SCHEMA public;

-- Move ai_usage table
ALTER TABLE IF EXISTS app.ai_usage SET SCHEMA public;

-- Verify tables are in public schema
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' AND table_name IN ('users', 'households', 'ai_usage')
ORDER BY table_name;
