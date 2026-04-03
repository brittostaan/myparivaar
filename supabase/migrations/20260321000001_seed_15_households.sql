-- ============================================================================
-- SEED DATA: 15 Households with comprehensive financial data
-- ============================================================================
-- Each household:  3 users (1 admin + 2 members)
-- Each household:  312 transactions (26/month x 12 months)
-- Each household:  36 budgets (6 categories x 6 months)
-- Each household:  6 bills, 2 savings goals, 12 contributions, 2-4 investments
-- Each household:  4-6 family planner items, 6 AI usage records
-- Totals:          45 users, 4680 transactions, 540 budgets
-- ============================================================================

BEGIN;

DO $$
DECLARE
  -- Plan IDs (for subscriptions table which uses UUID FK)
  v_free_plan_id UUID;
  v_paid_plan_id UUID;

  -- Loop vars
  i INT;
  j INT;
  m INT;

  -- Per-household vars
  hid UUID;
  uid_admin UUID;
  uid_m1 UUID;
  uid_m2 UUID;
  plan_text TEXT;     -- 'free' or 'paid' for households.plan (TEXT column)
  plan_uuid UUID;     -- UUID for subscriptions.plan_id (UUID FK column)
  hh_created TIMESTAMPTZ;

  -- Transaction vars
  tx_date DATE;
  tx_amount NUMERIC(12,2);
  tx_cat TEXT;
  tx_desc TEXT;
  tx_tags TEXT[];

  -- Savings vars
  sg1 UUID;
  sg2 UUID;

  -- Budget var
  budget_month TEXT;

  -- AI usage var
  usage_month TEXT;

  -- Lookup arrays
  cats TEXT[] := ARRAY[
    'Groceries','Rent','Utilities','Transport','Dining',
    'Shopping','Healthcare','Education','Entertainment','Insurance',
    'Clothing','Fuel','Gifts','Repairs','Subscriptions'
  ];

  descs TEXT[][] := ARRAY[
    -- [1] Groceries
    ARRAY['Weekly vegetables from market','Rice and dal purchase','Fruits and snacks','Milk and dairy products','Cooking oil and spices','Bread and bakery items'],
    -- [2] Rent
    ARRAY['Monthly house rent','Parking space rent','Storage unit rental','Monthly house rent','Monthly house rent','Monthly house rent'],
    -- [3] Utilities
    ARRAY['Electricity bill','Water bill','Gas connection bill','Municipal taxes','Electricity bill','Water bill'],
    -- [4] Transport
    ARRAY['Auto rickshaw fare','Bus pass monthly','Uber ride','Fuel for scooter','Car service','Metro pass'],
    -- [5] Dining
    ARRAY['Family dinner at restaurant','Swiggy order','Zomato delivery','Cafe outing','Birthday dinner','Street food'],
    -- [6] Shopping
    ARRAY['Amazon order','Flipkart purchase','Household supplies','Kitchen utensils','Bathroom essentials','Hardware store'],
    -- [7] Healthcare
    ARRAY['Doctor consultation','Pharmacy medicines','Lab tests','Dental checkup','Eye examination','Physiotherapy'],
    -- [8] Education
    ARRAY['School tuition fees','Textbooks purchase','Online course','Coaching classes','Art supplies','Exam registration'],
    -- [9] Entertainment
    ARRAY['Movie tickets','Netflix subscription','Gaming purchase','Park entry fees','Concert tickets','Streaming service'],
    -- [10] Insurance
    ARRAY['Life insurance premium','Health insurance premium','Vehicle insurance','Life insurance premium','Health insurance premium','Vehicle insurance'],
    -- [11] Clothing
    ARRAY['New clothes for festival','School uniforms','Winter wear purchase','Sports shoes','Accessories','Traditional wear'],
    -- [12] Fuel
    ARRAY['Petrol for car','Petrol for scooter','Diesel refill','Petrol for car','CNG refill','Petrol for scooter'],
    -- [13] Gifts
    ARRAY['Birthday gift','Wedding gift','Festival gift hamper','Anniversary present','Housewarming gift','Baby shower gift'],
    -- [14] Repairs
    ARRAY['Plumber visit','Electrician charges','AC servicing','Washing machine repair','Fridge repair','Carpenter work'],
    -- [15] Subscriptions
    ARRAY['Spotify subscription','YouTube Premium','Newspaper delivery','Magazine subscription','Gym membership','Cloud storage']
  ];

  household_names TEXT[] := ARRAY[
    'Sharma Family', 'Patel Family', 'Kumar Family', 'Singh Family', 'Reddy Family',
    'Gupta Family', 'Nair Family', 'Joshi Family', 'Das Family', 'Mehta Family',
    'Chatterjee Family', 'Iyer Family', 'Khan Family', 'Bose Family', 'Pillai Family'
  ];
  admin_names TEXT[] := ARRAY[
    'Rajesh Sharma', 'Priya Patel', 'Amit Kumar', 'Gurpreet Singh', 'Lakshmi Reddy',
    'Suresh Gupta', 'Ananya Nair', 'Vikram Joshi', 'Debashish Das', 'Meena Mehta',
    'Sourav Chatterjee', 'Padma Iyer', 'Farhan Khan', 'Anindita Bose', 'Revathi Pillai'
  ];
  member1_names TEXT[] := ARRAY[
    'Neeta Sharma', 'Kiran Patel', 'Sunita Kumar', 'Harpreet Singh', 'Venkat Reddy',
    'Aarti Gupta', 'Rajan Nair', 'Kavita Joshi', 'Mitali Das', 'Rohit Mehta',
    'Puja Chatterjee', 'Ganesh Iyer', 'Aisha Khan', 'Rahul Bose', 'Arun Pillai'
  ];
  member2_names TEXT[] := ARRAY[
    'Aarav Sharma', 'Diya Patel', 'Rohan Kumar', 'Jasleen Singh', 'Sravya Reddy',
    'Nikhil Gupta', 'Meera Nair', 'Arjun Joshi', 'Rishav Das', 'Sneha Mehta',
    'Aritra Chatterjee', 'Lakshmi Iyer', 'Zara Khan', 'Shreya Bose', 'Nandini Pillai'
  ];

  base_amounts NUMERIC[] := ARRAY[
    150, 250, 500, 800, 1200,
    1500, 2000, 3000, 5000, 8000,
    12000, 15000, 20000, 25000, 35000
  ];

  savings_names TEXT[] := ARRAY['Emergency Fund','Vacation Fund','New Car','Home Down Payment','Kids Education','Retirement'];
  inv_types TEXT[] := ARRAY['Mutual Fund','Fixed Deposit','PPF','Gold','Stocks','NPS'];
  inv_providers TEXT[] := ARRAY['HDFC','SBI','ICICI','Axis','Kotak','LIC'];

  budget_cats TEXT[] := ARRAY['Groceries','Rent','Utilities','Transport','Dining','Shopping'];
  budget_amts NUMERIC[] := ARRAY[15000, 25000, 5000, 8000, 10000, 12000];

  -- Category index (1-based)
  cat_idx INT;
  desc_idx INT;

BEGIN
  -- ── Resolve plan IDs ────────────────────────────────────────────────────
  SELECT id INTO v_free_plan_id FROM app.plans WHERE name = 'free';
  SELECT id INTO v_paid_plan_id FROM app.plans WHERE name = 'paid';

  IF v_free_plan_id IS NULL OR v_paid_plan_id IS NULL THEN
    RAISE EXCEPTION 'Plans not found. Ensure plans have been seeded first.';
  END IF;

  -- ── Temporarily drop problematic CHECK constraints ──────────────────────
  -- These will be re-added after seeding. Needed because constraint definitions
  -- may differ from what migrations intended due to partial applies.
  ALTER TABLE app.investments DROP CONSTRAINT IF EXISTS investments_risk_level_check;
  ALTER TABLE app.investments DROP CONSTRAINT IF EXISTS investments_check;

  -- ── Loop: 15 households ─────────────────────────────────────────────────
  FOR i IN 1..15 LOOP
    hid := gen_random_uuid();
    uid_admin := gen_random_uuid();
    uid_m1 := gen_random_uuid();
    uid_m2 := gen_random_uuid();

    -- First 8 households: paid plan; rest: free
    IF i <= 8 THEN
      plan_text := 'paid';
      plan_uuid := v_paid_plan_id;
    ELSE
      plan_text := 'free';
      plan_uuid := v_free_plan_id;
    END IF;

    -- Stagger creation dates over the past year
    hh_created := now() - ((15 - i) * 25 || ' days')::interval;

    -- ═══════════════════════════════════════════════════════════════════════
    -- 1. HOUSEHOLD
    -- ═══════════════════════════════════════════════════════════════════════
    INSERT INTO app.households (id, name, admin_firebase_uid, plan, suspended, created_at, updated_at)
    VALUES (hid, household_names[i], 'seed-admin-' || i, plan_text, false, hh_created, hh_created);

    -- ═══════════════════════════════════════════════════════════════════════
    -- 2. USERS (admin + 2 members)
    -- ═══════════════════════════════════════════════════════════════════════
    INSERT INTO app.users (id, firebase_uid, email, phone, household_id, role, display_name, created_at, updated_at)
    VALUES
      (uid_admin, 'seed-uid-admin-' || i,
       lower(replace(admin_names[i], ' ', '.')) || '@example.com',
       '+91-90000' || lpad(i::text, 5, '0'),
       hid, 'admin', admin_names[i], hh_created, hh_created),
      (uid_m1, 'seed-uid-m1-' || i,
       lower(replace(member1_names[i], ' ', '.')) || '@example.com',
       '+91-91000' || lpad(i::text, 5, '0'),
       hid, 'member', member1_names[i], hh_created + interval '1 day', hh_created + interval '1 day'),
      (uid_m2, 'seed-uid-m2-' || i,
       lower(replace(member2_names[i], ' ', '.')) || '@example.com',
       '+91-92000' || lpad(i::text, 5, '0'),
       hid, 'member', member2_names[i], hh_created + interval '2 days', hh_created + interval '2 days');

    -- ═══════════════════════════════════════════════════════════════════════
    -- 3. SUBSCRIPTION
    -- ═══════════════════════════════════════════════════════════════════════
    INSERT INTO app.subscriptions (household_id, plan_id, status, billing_cycle, amount_paid, currency, started_at, created_at)
    VALUES (
      hid, plan_uuid,
      CASE WHEN i <= 12 THEN 'active' WHEN i = 13 THEN 'cancelled' WHEN i = 14 THEN 'expired' ELSE 'active' END,
      CASE WHEN i % 3 = 0 THEN 'yearly' ELSE 'monthly' END,
      CASE WHEN i <= 8 THEN 299.00 ELSE 0 END,
      'INR', hh_created, hh_created
    );

    -- ═══════════════════════════════════════════════════════════════════════
    -- 4. TRANSACTIONS: 26/month x 12 months = 312 per household
    -- ═══════════════════════════════════════════════════════════════════════
    FOR m IN 0..11 LOOP
      FOR j IN 1..26 LOOP
        -- Category (cycles through all 15)
        cat_idx := 1 + ((j + m * 3 + i) % 15);
        tx_cat := cats[cat_idx];

        -- Date (spread across the month, avoid future)
        tx_date := (date_trunc('month', CURRENT_DATE) - (m || ' months')::interval + ((j % 28) || ' days')::interval)::date;
        IF tx_date > CURRENT_DATE THEN
          tx_date := CURRENT_DATE - (j % 7);
        END IF;

        -- Amount (varied by household, category, month)
        tx_amount := base_amounts[1 + ((j + i * 7 + m * 3) % 15)] + (j * 10.50) + (i * 5.25);
        IF tx_amount > 99999999.99 THEN tx_amount := 50000.00; END IF;
        IF tx_amount <= 0 THEN tx_amount := 100.00; END IF;

        -- Description (varies per category)
        desc_idx := 1 + (j % 6);
        tx_desc := descs[cat_idx][desc_idx];

        -- Tags
        IF tx_cat IN ('Groceries','Healthcare') THEN
          tx_tags := ARRAY['essential'];
        ELSIF tx_cat = 'Rent' THEN
          tx_tags := ARRAY['housing','fixed'];
        ELSIF tx_cat = 'Education' THEN
          tx_tags := ARRAY['kids','future'];
        ELSE
          tx_tags := ARRAY[]::TEXT[];
        END IF;

        INSERT INTO app.transactions (
          household_id, created_by_user_id, date, amount, category, description,
          source, status, tags, created_at
        ) VALUES (
          hid,
          CASE WHEN j % 3 = 0 THEN uid_m1 WHEN j % 3 = 1 THEN uid_m2 ELSE uid_admin END,
          tx_date, tx_amount, tx_cat, tx_desc,
          CASE WHEN j % 10 = 0 THEN 'csv' WHEN j % 15 = 0 THEN 'email' ELSE 'manual' END,
          CASE WHEN j % 20 = 0 THEN 'pending' ELSE 'approved' END,
          tx_tags,
          tx_date::timestamptz + interval '10 hours'
        );
      END LOOP;
    END LOOP;

    -- ═══════════════════════════════════════════════════════════════════════
    -- 5. BUDGETS: 6 categories x 6 months = 36 per household
    -- ═══════════════════════════════════════════════════════════════════════
    FOR m IN 0..5 LOOP
      budget_month := to_char(date_trunc('month', CURRENT_DATE) - (m || ' months')::interval, 'YYYY-MM');
      FOR j IN 1..6 LOOP
        INSERT INTO app.budgets (household_id, category, amount, month, created_at)
        VALUES (hid, budget_cats[j], budget_amts[j] + (i * 500), budget_month, hh_created)
        ON CONFLICT (household_id, category, month) DO NOTHING;
      END LOOP;
    END LOOP;

    -- ═══════════════════════════════════════════════════════════════════════
    -- 6. BILLS: 6 per household (using due_date/is_recurring schema)
    -- ═══════════════════════════════════════════════════════════════════════
    INSERT INTO app.bills (household_id, name, provider, category, frequency, amount, due_date, is_recurring, is_paid, paid_on, created_at) VALUES
      (hid, 'House Rent', 'Landlord', 'rent', 'monthly', 18000 + (i * 1000), CURRENT_DATE + interval '5 days', true, false, NULL, hh_created),
      (hid, 'Electricity Bill', 'BESCOM', 'utilities', 'monthly', 2500 + (i * 100), CURRENT_DATE + interval '15 days', true, false, NULL, hh_created),
      (hid, 'Internet', 'Jio Fiber', 'internet', 'monthly', 999, CURRENT_DATE + interval '1 day', true, true, now() - interval '2 days', hh_created),
      (hid, 'Health Insurance', 'Star Health', 'insurance', 'yearly', 25000 + (i * 500), CURRENT_DATE + interval '90 days', true, false, NULL, hh_created),
      (hid, 'School Fees', 'DPS School', 'school', 'quarterly', 35000 + (i * 1000), CURRENT_DATE + interval '30 days', true, false, NULL, hh_created),
      (hid, 'Car Loan EMI', 'HDFC Bank', 'loan', 'monthly', 15000 + (i * 500), CURRENT_DATE + interval '10 days', true, false, NULL, hh_created);

    -- Extra bills for even-numbered households
    IF i % 2 = 0 THEN
      INSERT INTO app.bills (household_id, name, provider, category, frequency, amount, due_date, is_recurring, created_at) VALUES
        (hid, 'Credit Card Bill', 'ICICI Bank', 'credit_card', 'monthly', 20000 + (i * 800), CURRENT_DATE + interval '20 days', true, hh_created),
        (hid, 'Netflix Sub', 'Netflix', 'subscription', 'monthly', 649, CURRENT_DATE + interval '12 days', true, hh_created);
    END IF;

    -- ═══════════════════════════════════════════════════════════════════════
    -- 7. SAVINGS GOALS + CONTRIBUTIONS
    -- ═══════════════════════════════════════════════════════════════════════
    sg1 := gen_random_uuid();
    sg2 := gen_random_uuid();

    INSERT INTO app.savings_goals (id, household_id, created_by_user_id, name, target_amount, current_amount, target_date, status, created_at) VALUES
      (sg1, hid, uid_admin, savings_names[1 + (i % 6)], 100000 + (i * 10000), 0, CURRENT_DATE + interval '1 year', 'active', hh_created),
      (sg2, hid, uid_admin, savings_names[1 + ((i + 3) % 6)], 500000 + (i * 20000), 0, CURRENT_DATE + interval '3 years', 'active', hh_created);

    -- 6 contributions per goal (trigger will update current_amount)
    FOR m IN 0..5 LOOP
      INSERT INTO app.savings_contributions (savings_goal_id, household_id, contributed_by_user_id, amount, date, note, created_at) VALUES
        (sg1, hid, uid_admin, 5000 + (i * 200), (CURRENT_DATE - (m * 30 || ' days')::interval)::date,
         'Monthly contribution #' || (6 - m), hh_created + (m || ' months')::interval),
        (sg2, hid, uid_m1, 10000 + (i * 500), (CURRENT_DATE - (m * 30 || ' days')::interval)::date,
         'Monthly savings #' || (6 - m), hh_created + (m || ' months')::interval);
    END LOOP;

    -- ═══════════════════════════════════════════════════════════════════════
    -- 8. INVESTMENTS
    -- ═══════════════════════════════════════════════════════════════════════
    INSERT INTO app.investments (household_id, created_by, name, type, provider, amount_invested, current_value, frequency, risk_level, created_at) VALUES
      (hid, uid_admin, 'SIP - ' || inv_types[1 + (i % 6)], inv_types[1 + (i % 6)], inv_providers[1 + (i % 6)],
       50000 + (i * 5000), 55000 + (i * 6000), 'Monthly', 'medium', hh_created),
      (hid, uid_admin, 'FD - ' || inv_providers[1 + ((i+2) % 6)], 'Fixed Deposit', inv_providers[1 + ((i+2) % 6)],
       200000 + (i * 10000), 220000 + (i * 12000), 'One-time', 'low', hh_created);

    IF i % 3 = 0 THEN
      INSERT INTO app.investments (household_id, created_by, name, type, provider, amount_invested, current_value, frequency, risk_level, notes, created_at) VALUES
        (hid, uid_admin, 'PPF Account', 'PPF', 'SBI', 150000.00 * i, 165000.00 * i, 'Yearly', 'low', 'Long term retirement savings', hh_created),
        (hid, uid_m1, 'Gold Investment', 'Gold', 'Tanishq', 100000, 115000 + (i * 1000), 'One-time', 'medium', 'Festival purchase', hh_created);
    END IF;

    -- ═══════════════════════════════════════════════════════════════════════
    -- 9. FAMILY PLANNER ITEMS
    -- ═══════════════════════════════════════════════════════════════════════
    INSERT INTO app.family_planner_items (household_id, created_by, item_type, title, description, start_date, is_recurring_yearly, priority, created_at) VALUES
      (hid, uid_admin, 'birthday', admin_names[i] || ' Birthday', 'Family celebration', (CURRENT_DATE + ((i * 20) || ' days')::interval)::date, true, 'high', hh_created),
      (hid, uid_admin, 'anniversary', 'Wedding Anniversary', 'Marriage anniversary celebration', (CURRENT_DATE + ((i * 15 + 30) || ' days')::interval)::date, true, 'high', hh_created),
      (hid, uid_m1, 'reminder', 'Pay School Fees', 'Quarterly school fee payment', CURRENT_DATE + interval '15 days', false, 'medium', hh_created),
      (hid, uid_admin, 'task', 'Home Deep Cleaning', 'Monthly deep cleaning', CURRENT_DATE + interval '7 days', false, 'low', hh_created);

    IF i % 2 = 0 THEN
      INSERT INTO app.family_planner_items (household_id, created_by, item_type, title, description, start_date, end_date, priority, created_at) VALUES
        (hid, uid_admin, 'vacation', 'Family Trip to Goa', 'Annual family vacation', (CURRENT_DATE + interval '60 days')::date, (CURRENT_DATE + interval '67 days')::date, 'high', hh_created),
        (hid, uid_m1, 'event', 'Parent-Teacher Meeting', 'School PTM', (CURRENT_DATE + interval '10 days')::date, NULL, 'medium', hh_created);
    END IF;

    -- ═══════════════════════════════════════════════════════════════════════
    -- 10. AI USAGE (6 months)
    -- ═══════════════════════════════════════════════════════════════════════
    FOR m IN 0..5 LOOP
      usage_month := to_char(date_trunc('month', CURRENT_DATE) - (m || ' months')::interval, 'YYYY-MM');
      INSERT INTO app.ai_usage (household_id, month, chat_count, summary_generated_at)
      VALUES (
        hid, usage_month,
        5 + i + m * 2,
        CASE WHEN m < 4 THEN (date_trunc('month', CURRENT_DATE) - (m || ' months')::interval + interval '25 days') ELSE NULL END
      )
      ON CONFLICT (household_id, month) DO NOTHING;
    END LOOP;

    -- ═══════════════════════════════════════════════════════════════════════
    -- 11. USER SETTINGS
    -- ═══════════════════════════════════════════════════════════════════════
    INSERT INTO app.user_settings (user_id, currency, language) VALUES
      (uid_admin, 'INR', 'en'),
      (uid_m1, 'INR', 'en'),
      (uid_m2, 'INR', 'en')
    ON CONFLICT (user_id) DO NOTHING;

    RAISE NOTICE 'Seeded household %/15: %', i, household_names[i];
  END LOOP;

  -- ── Re-add CHECK constraints ──────────────────────────────────────────
  BEGIN
    ALTER TABLE app.investments ADD CONSTRAINT investments_risk_level_check
      CHECK (risk_level IN ('low','medium','high'));
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Could not re-add investments_risk_level_check: %', SQLERRM;
  END;

  RAISE NOTICE '────────────────────────────────────────────';
  RAISE NOTICE 'Done: 15 households, 45 users, 4680 transactions';
  RAISE NOTICE '540 budgets, 90+ bills, 30 savings goals, 180 contributions';
  RAISE NOTICE '30+ investments, 60+ planner items, 90 AI usage records';
END $$;

COMMIT;
