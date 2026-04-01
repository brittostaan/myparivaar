-- ============================================================================
-- Dynamic demo transactions for Devi's household
-- Replaces the static April 2026 seed with a function + pg_cron job
-- that auto-generates 10 realistic transactions for the current month.
-- ============================================================================

-- 1. Enable pg_cron (idempotent)
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- 2. Delete the old static April 2026 records
DELETE FROM app.transactions
WHERE household_id = '7866c082-08d5-495f-83fc-212fcf7068ca'
  AND created_by_user_id = '4547e538-d338-474a-881e-be570525fd57'
  AND date >= '2026-04-01' AND date <= '2026-04-30'
  AND source = 'manual';

-- 3. Create the function that seeds 10 transactions for the current month
CREATE OR REPLACE FUNCTION app.seed_demo_transactions()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_hid         UUID := '7866c082-08d5-495f-83fc-212fcf7068ca';
  v_uid         UUID := '4547e538-d338-474a-881e-be570525fd57';
  v_month_start DATE := date_trunc('month', CURRENT_DATE)::date;
  v_day_max     INT  := LEAST(EXTRACT(DAY FROM CURRENT_DATE)::int, 28);
BEGIN
  -- Remove any previous demo transactions for this month
  DELETE FROM app.transactions
  WHERE household_id = v_hid
    AND created_by_user_id = v_uid
    AND date >= v_month_start
    AND date < (v_month_start + INTERVAL '1 month')::date
    AND description LIKE '%[demo]%';

  -- 10 transactions spread across the month, clamped to days elapsed
  INSERT INTO app.transactions (household_id, created_by_user_id, date, amount, category, description, source, status, tags)
  VALUES
    (v_hid, v_uid, v_month_start + LEAST(0,  v_day_max - 1), 2450.00, 'Groceries',        'Weekly vegetables and fruits from market [demo]',              'manual', 'approved', ARRAY['essential','weekly']),
    (v_hid, v_uid, v_month_start + LEAST(2,  v_day_max - 1),  899.00, 'Entertainment',     'Movie tickets for family outing [demo]',                       'manual', 'approved', ARRAY['family','weekend']),
    (v_hid, v_uid, v_month_start + LEAST(4,  v_day_max - 1), 3500.00, 'Education',         'Monthly tuition fee payment [demo]',                           'manual', 'approved', ARRAY['recurring','education']),
    (v_hid, v_uid, v_month_start + LEAST(6,  v_day_max - 1), 1200.00, 'Personal Care',     'Salon and grooming session [demo]',                            'manual', 'approved', ARRAY['self-care']),
    (v_hid, v_uid, v_month_start + LEAST(9,  v_day_max - 1), 5800.00, 'Physical Wellness', 'Gym membership renewal quarterly [demo]',                      'manual', 'approved', ARRAY['health','quarterly']),
    (v_hid, v_uid, v_month_start + LEAST(11, v_day_max - 1),  750.00, 'Convenience Food',  'Swiggy and Zomato orders this week [demo]',                    'manual', 'approved', ARRAY['food','delivery']),
    (v_hid, v_uid, v_month_start + LEAST(14, v_day_max - 1), 4200.00, 'Senior Care',       'Medicines and health supplements for parents [demo]',          'manual', 'approved', ARRAY['parents','health']),
    (v_hid, v_uid, v_month_start + LEAST(17, v_day_max - 1), 1850.00, 'Pet Care',          'Vet checkup and dog food supplies [demo]',                     'manual', 'approved', ARRAY['pet','monthly']),
    (v_hid, v_uid, v_month_start + LEAST(21, v_day_max - 1), 6500.00, 'Vacation',          'Weekend getaway hotel booking Lonavala [demo]',                'manual', 'approved', ARRAY['travel','weekend']),
    (v_hid, v_uid, v_month_start + LEAST(24, v_day_max - 1), 2100.00, 'Mental Wellness',   'Therapy session and mindfulness app subscription [demo]',      'manual', 'approved', ARRAY['mental-health','subscription']);
END;
$$;

-- 4. Run immediately for the current month
SELECT app.seed_demo_transactions();

-- 5. Schedule: run on the 1st of every month at 00:05 UTC
SELECT cron.schedule(
  'seed-demo-transactions',          -- job name
  '5 0 1 * *',                       -- cron: minute 5, hour 0, day 1, every month
  $$SELECT app.seed_demo_transactions()$$
);
