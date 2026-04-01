-- Remove demo transactions and disable the demo cron job
-- This switches to real user data only

-- 1. Unschedule the demo cron job
SELECT cron.unschedule('seed-demo-transactions');

-- 2. Delete all demo transactions (tagged with [demo] in description)
DELETE FROM app.transactions
WHERE description LIKE '%[demo]%';

-- 3. Drop the seed function
DROP FUNCTION IF EXISTS app.seed_demo_transactions();
