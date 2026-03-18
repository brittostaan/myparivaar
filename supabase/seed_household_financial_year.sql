-- Seed one year of dummy household finance data.
-- Intended for dev / preview databases only.
--
-- Usage in Supabase SQL Editor:
-- 1. Open this file.
-- 2. Update v_household_name if needed.
-- 3. Run the whole script.

DO $seed$
DECLARE
  v_household_name TEXT := 'Devi''s Family';
  v_seed_marker TEXT := 'seed:household-financial-year-v1';
  v_household_id UUID;
  v_user_id UUID;
  v_risk_constraint TEXT;
  v_risk_low TEXT := 'low';
  v_risk_medium TEXT := 'medium';
  v_risk_high TEXT := 'high';
  v_start_date DATE := (CURRENT_DATE - INTERVAL '364 days')::date;
  v_start_month DATE := (date_trunc('month', CURRENT_DATE) - INTERVAL '11 months')::date;
BEGIN
  SELECT h.id, u.id
  INTO v_household_id, v_user_id
  FROM app.households h
  JOIN LATERAL (
    SELECT id
    FROM app.users
    WHERE household_id = h.id
      AND deleted_at IS NULL
    ORDER BY created_at
    LIMIT 1
  ) u ON true
  WHERE h.deleted_at IS NULL
    AND (v_household_name IS NULL OR h.name = v_household_name)
  ORDER BY h.created_at
  LIMIT 1;

  IF v_household_id IS NULL OR v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unable to resolve a household and user. Update v_household_name in supabase/seed_household_financial_year.sql';
  END IF;

  SELECT pg_get_constraintdef(c.oid)
  INTO v_risk_constraint
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = 'app'
    AND t.relname = 'investments'
    AND c.conname = 'investments_risk_level_check'
  LIMIT 1;

  IF v_risk_constraint ILIKE '%''Low''%' THEN
    v_risk_low := 'Low';
    v_risk_medium := 'Medium';
    v_risk_high := 'High';
  ELSIF v_risk_constraint ILIKE '%''LOW''%' THEN
    v_risk_low := 'LOW';
    v_risk_medium := 'MEDIUM';
    v_risk_high := 'HIGH';
  END IF;

  -- Remove prior seed data from the same script so reruns stay clean.
  DELETE FROM app.transactions
  WHERE household_id = v_household_id
    AND notes = v_seed_marker;

  DELETE FROM app.investments
  WHERE household_id = v_household_id
    AND notes = v_seed_marker;

  DELETE FROM app.bills
  WHERE household_id = v_household_id
    AND notes = v_seed_marker;

  DELETE FROM app.savings_goals
  WHERE household_id = v_household_id
    AND name IN (
      'Emergency Fund',
      'Vacation Fund',
      'Car Upgrade',
      'Education Reserve'
    );

  DELETE FROM app.family_planner_items
  WHERE household_id = v_household_id
    AND coalesce(description, '') LIKE '%' || v_seed_marker || '%';

  DELETE FROM app.budgets
  WHERE household_id = v_household_id
    AND month >= to_char(v_start_month, 'YYYY-MM')
    AND category IN (
      'Housing',
      'Food',
      'Transport',
      'Utilities',
      'Entertainment',
      'Shopping',
      'Healthcare',
      'Education'
    );

  -- Monthly salary credits so dashboard savings calculations have income data.
  INSERT INTO app.transactions (
    household_id,
    created_by_user_id,
    date,
    amount,
    category,
    description,
    notes,
    source,
    status
  )
  SELECT
    v_household_id,
    v_user_id,
    (month_start + INTERVAL '1 day')::date,
    (82000 + ((row_number() OVER ()) * 750))::NUMERIC(12,2),
    'salary',
    'Monthly salary credit',
    v_seed_marker,
    'manual',
    'approved'
  FROM generate_series(
    v_start_month::timestamp,
    date_trunc('month', CURRENT_DATE)::timestamp,
    INTERVAL '1 month'
  ) month_start;

  -- Housing / rent once per month.
  INSERT INTO app.transactions (
    household_id,
    created_by_user_id,
    date,
    amount,
    category,
    description,
    notes,
    source,
    status
  )
  SELECT
    v_household_id,
    v_user_id,
    (month_start + INTERVAL '4 day')::date,
    18000.00,
    'Housing',
    'Monthly house rent',
    v_seed_marker,
    'manual',
    'approved'
  FROM generate_series(
    v_start_month::timestamp,
    date_trunc('month', CURRENT_DATE)::timestamp,
    INTERVAL '1 month'
  ) month_start;

  -- Utilities once per month.
  INSERT INTO app.transactions (
    household_id,
    created_by_user_id,
    date,
    amount,
    category,
    description,
    notes,
    source,
    status
  )
  SELECT
    v_household_id,
    v_user_id,
    (month_start + INTERVAL '9 day')::date,
    (2200 + ((extract(month FROM month_start)::INT % 3) * 250))::NUMERIC(12,2),
    'Utilities',
    'Electricity and water bills',
    v_seed_marker,
    'manual',
    'approved'
  FROM generate_series(
    v_start_month::timestamp,
    date_trunc('month', CURRENT_DATE)::timestamp,
    INTERVAL '1 month'
  ) month_start;

  -- Education once per month.
  INSERT INTO app.transactions (
    household_id,
    created_by_user_id,
    date,
    amount,
    category,
    description,
    notes,
    source,
    status
  )
  SELECT
    v_household_id,
    v_user_id,
    (month_start + INTERVAL '14 day')::date,
    3500.00,
    'Education',
    'School and learning expenses',
    v_seed_marker,
    'manual',
    'approved'
  FROM generate_series(
    v_start_month::timestamp,
    date_trunc('month', CURRENT_DATE)::timestamp,
    INTERVAL '1 month'
  ) month_start;

  -- Grocery / food every 3 days.
  INSERT INTO app.transactions (
    household_id,
    created_by_user_id,
    date,
    amount,
    category,
    description,
    notes,
    source,
    status
  )
  SELECT
    v_household_id,
    v_user_id,
    tx_date::date,
    (350 + ((extract(doy FROM tx_date)::INT % 5) * 95))::NUMERIC(12,2),
    'Food',
    CASE WHEN extract(isodow FROM tx_date) IN (6, 7)
      THEN 'Family dining and groceries'
      ELSE 'Groceries and essentials'
    END,
    v_seed_marker,
    'manual',
    'approved'
  FROM generate_series(v_start_date::timestamp, CURRENT_DATE::timestamp, INTERVAL '3 day') tx_date;

  -- Transport on most weekdays.
  INSERT INTO app.transactions (
    household_id,
    created_by_user_id,
    date,
    amount,
    category,
    description,
    notes,
    source,
    status
  )
  SELECT
    v_household_id,
    v_user_id,
    tx_date::date,
    (120 + ((extract(doy FROM tx_date)::INT % 4) * 40))::NUMERIC(12,2),
    'Transport',
    'Fuel, cab, and commute costs',
    v_seed_marker,
    'manual',
    'approved'
  FROM generate_series(v_start_date::timestamp, CURRENT_DATE::timestamp, INTERVAL '2 day') tx_date
  WHERE extract(isodow FROM tx_date) <= 6;

  -- Shopping twice a month.
  INSERT INTO app.transactions (
    household_id,
    created_by_user_id,
    date,
    amount,
    category,
    description,
    notes,
    source,
    status
  )
  SELECT
    v_household_id,
    v_user_id,
    shopping_date::date,
    (1200 + ((extract(month FROM shopping_date)::INT % 4) * 300))::NUMERIC(12,2),
    'Shopping',
    'Household and personal shopping',
    v_seed_marker,
    'manual',
    'approved'
  FROM (
    SELECT (month_start + INTERVAL '17 day') AS shopping_date
    FROM generate_series(
      v_start_month::timestamp,
      date_trunc('month', CURRENT_DATE)::timestamp,
      INTERVAL '1 month'
    ) month_start
    UNION ALL
    SELECT (month_start + INTERVAL '24 day') AS shopping_date
    FROM generate_series(
      v_start_month::timestamp,
      date_trunc('month', CURRENT_DATE)::timestamp,
      INTERVAL '1 month'
    ) month_start
  ) shopping_rows;

  -- Entertainment every other weekend.
  INSERT INTO app.transactions (
    household_id,
    created_by_user_id,
    date,
    amount,
    category,
    description,
    notes,
    source,
    status
  )
  SELECT
    v_household_id,
    v_user_id,
    tx_date::date,
    (700 + ((extract(month FROM tx_date)::INT % 3) * 250))::NUMERIC(12,2),
    'Entertainment',
    'Movies, outings, and subscriptions',
    v_seed_marker,
    'manual',
    'approved'
  FROM generate_series(v_start_date::timestamp, CURRENT_DATE::timestamp, INTERVAL '14 day') tx_date;

  -- Healthcare once every two months.
  INSERT INTO app.transactions (
    household_id,
    created_by_user_id,
    date,
    amount,
    category,
    description,
    notes,
    source,
    status
  )
  SELECT
    v_household_id,
    v_user_id,
    (month_start + INTERVAL '20 day')::date,
    (900 + ((extract(month FROM month_start)::INT % 5) * 180))::NUMERIC(12,2),
    'Healthcare',
    'Medicines and doctor visits',
    v_seed_marker,
    'manual',
    'approved'
  FROM generate_series(
    v_start_month::timestamp,
    date_trunc('month', CURRENT_DATE)::timestamp,
    INTERVAL '2 month'
  ) month_start;

  -- Budgets for the last 12 months.
  INSERT INTO app.budgets (
    household_id,
    imported_by_user_id,
    category,
    amount,
    month
  )
  SELECT
    v_household_id,
    v_user_id,
    budget_rows.category,
    budget_rows.amount,
    to_char(month_start, 'YYYY-MM')
  FROM generate_series(
    v_start_month::timestamp,
    date_trunc('month', CURRENT_DATE)::timestamp,
    INTERVAL '1 month'
  ) month_start
  CROSS JOIN (
    VALUES
      ('Housing', 18000.00::NUMERIC(12,2)),
      ('Food', 9000.00::NUMERIC(12,2)),
      ('Transport', 4200.00::NUMERIC(12,2)),
      ('Utilities', 3200.00::NUMERIC(12,2)),
      ('Entertainment', 2800.00::NUMERIC(12,2)),
      ('Shopping', 4500.00::NUMERIC(12,2)),
      ('Healthcare', 2000.00::NUMERIC(12,2)),
      ('Education', 5000.00::NUMERIC(12,2))
  ) AS budget_rows(category, amount)
  ON CONFLICT (household_id, category, month)
  DO UPDATE SET
    amount = EXCLUDED.amount,
    imported_by_user_id = EXCLUDED.imported_by_user_id,
    updated_at = now(),
    deleted_at = NULL;

  -- Bills used by the bills dashboard.
  INSERT INTO app.bills (
    household_id,
    name,
    provider,
    category,
    frequency,
    amount,
    due_date,
    is_recurring,
    is_paid,
    notes
  )
  VALUES
    (v_household_id, 'House Rent', 'Landlord', 'rent', 'monthly', 18000.00, CURRENT_DATE + 5, true, false, v_seed_marker),
    (v_household_id, 'Electricity Bill', 'TNEB', 'utilities', 'monthly', 1850.00, CURRENT_DATE + 7, true, false, v_seed_marker),
    (v_household_id, 'Internet Bill', 'Airtel', 'internet', 'monthly', 999.00, CURRENT_DATE + 10, true, false, v_seed_marker),
    (v_household_id, 'Health Insurance', 'Star Health', 'insurance', 'yearly', 18500.00, CURRENT_DATE + 25, true, false, v_seed_marker),
    (v_household_id, 'School Fee', 'ABC Public School', 'school', 'quarterly', 24000.00, CURRENT_DATE + 18, true, false, v_seed_marker),
    (v_household_id, 'Streaming Bundle', 'OTT Apps', 'subscription', 'monthly', 699.00, CURRENT_DATE + 12, true, true, v_seed_marker);

  -- Savings goals.
  INSERT INTO app.savings_goals (
    household_id,
    name,
    target_amount,
    current_amount,
    target_date
  )
  VALUES
    (v_household_id, 'Emergency Fund', 300000.00, 120000.00, CURRENT_DATE + 240),
    (v_household_id, 'Vacation Fund', 150000.00, 45000.00, CURRENT_DATE + 180),
    (v_household_id, 'Car Upgrade', 600000.00, 175000.00, CURRENT_DATE + 420),
    (v_household_id, 'Education Reserve', 250000.00, 80000.00, CURRENT_DATE + 365);

  -- Investments. Omit risk_level so the deployed default handles schema drift safely.
  INSERT INTO app.investments (
    household_id,
    created_by,
    name,
    type,
    provider,
    amount_invested,
    current_value,
    due_date,
    maturity_date,
    frequency,
    risk_level,
    notes,
    child_name
  )
  VALUES
    (v_household_id, v_user_id, 'Family Protection Plan', 'Insurance', 'HDFC Life', 50000.00, 52750.00, CURRENT_DATE + 40, CURRENT_DATE + 3650, 'Monthly', v_risk_low, v_seed_marker, NULL),
    (v_household_id, v_user_id, 'Equity Growth SIP', 'Mutual Fund', 'ICICI Prudential', 180000.00, 214500.00, CURRENT_DATE + 30, CURRENT_DATE + 1825, 'Monthly', v_risk_medium, v_seed_marker, NULL),
    (v_household_id, v_user_id, 'Bluechip Stocks', 'Equity', 'Zerodha', 220000.00, 247800.00, NULL, CURRENT_DATE + 1460, 'One-time', v_risk_high, v_seed_marker, NULL),
    (v_household_id, v_user_id, 'Family Fixed Deposit', 'Fixed Deposit', 'ICICI Bank', 300000.00, 318000.00, CURRENT_DATE + 15, CURRENT_DATE + 540, 'Quarterly', v_risk_low, v_seed_marker, NULL),
    (v_household_id, v_user_id, 'Gold Savings', 'Gold', 'MMTC', 125000.00, 139600.00, NULL, CURRENT_DATE + 1095, 'Monthly', v_risk_low, v_seed_marker, NULL);

  -- Family planner items for birthdays / anniversaries / events.
  INSERT INTO app.family_planner_items (
    household_id,
    created_by,
    item_type,
    title,
    description,
    start_date,
    end_date,
    is_all_day,
    is_completed,
    is_recurring_yearly,
    priority,
    location
  )
  VALUES
    (v_household_id, v_user_id, 'birthday', 'Aarav Birthday', 'Family birthday reminder · ' || v_seed_marker, CURRENT_DATE + 22, NULL, true, false, true, 'medium', 'Home'),
    (v_household_id, v_user_id, 'anniversary', 'Parents Anniversary', 'Anniversary reminder · ' || v_seed_marker, CURRENT_DATE + 45, NULL, true, false, true, 'high', 'Temple'),
    (v_household_id, v_user_id, 'vacation', 'Summer Vacation', 'Planned family trip · ' || v_seed_marker, CURRENT_DATE + 70, CURRENT_DATE + 75, true, false, false, 'medium', 'Ooty'),
    (v_household_id, v_user_id, 'event', 'School Annual Day', 'School event · ' || v_seed_marker, CURRENT_DATE + 90, NULL, true, false, false, 'medium', 'School Auditorium'),
    (v_household_id, v_user_id, 'reminder', 'Renew health policy', 'Insurance renewal reminder · ' || v_seed_marker, CURRENT_DATE + 25, NULL, true, false, true, 'high', NULL),
    (v_household_id, v_user_id, 'task', 'Plan Diwali shopping', 'Festival prep task · ' || v_seed_marker, CURRENT_DATE + 120, NULL, true, false, false, 'low', 'Mall');

  RAISE NOTICE 'Seed complete for household %, user %', v_household_id, v_user_id;
END;
$seed$;

WITH target_household AS (
  SELECT id
  FROM app.households
  WHERE name = 'Devi''s Family'
  LIMIT 1
)
SELECT 'transactions' AS dataset, COUNT(*) AS row_count
FROM app.transactions
WHERE household_id = (SELECT id FROM target_household)
  AND notes = 'seed:household-financial-year-v1'

UNION ALL

SELECT 'budgets' AS dataset, COUNT(*) AS row_count
FROM app.budgets
WHERE household_id = (SELECT id FROM target_household)
  AND category IN ('Housing', 'Food', 'Transport', 'Utilities', 'Entertainment', 'Shopping', 'Healthcare', 'Education')
  AND month >= to_char((date_trunc('month', CURRENT_DATE) - INTERVAL '11 months')::date, 'YYYY-MM')

UNION ALL

SELECT 'bills' AS dataset, COUNT(*) AS row_count
FROM app.bills
WHERE household_id = (SELECT id FROM target_household)
  AND notes = 'seed:household-financial-year-v1'

UNION ALL

SELECT 'savings_goals' AS dataset, COUNT(*) AS row_count
FROM app.savings_goals
WHERE household_id = (SELECT id FROM target_household)
  AND name IN ('Emergency Fund', 'Vacation Fund', 'Car Upgrade', 'Education Reserve')

UNION ALL

SELECT 'investments' AS dataset, COUNT(*) AS row_count
FROM app.investments
WHERE household_id = (SELECT id FROM target_household)
  AND notes = 'seed:household-financial-year-v1'

UNION ALL

SELECT 'family_planner_items' AS dataset, COUNT(*) AS row_count
FROM app.family_planner_items
WHERE household_id = (SELECT id FROM target_household)
  AND coalesce(description, '') LIKE '%seed:household-financial-year-v1%';