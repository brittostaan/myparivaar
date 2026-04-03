-- Seed 10 transactions for April 2026 for Devi's household
-- Devi's household_id: 7866c082-08d5-495f-83fc-212fcf7068ca
-- Devi's user_id: 4547e538-d338-474a-881e-be570525fd57

INSERT INTO app.transactions (household_id, created_by_user_id, date, amount, category, description, source, status, tags)
VALUES
  ('7866c082-08d5-495f-83fc-212fcf7068ca', '4547e538-d338-474a-881e-be570525fd57', '2026-04-01', 2450.00, 'Groceries',        'Weekly vegetables and fruits from market',              'manual', 'approved', ARRAY['essential','weekly']),
  ('7866c082-08d5-495f-83fc-212fcf7068ca', '4547e538-d338-474a-881e-be570525fd57', '2026-04-03',  899.00, 'Entertainment',     'Movie tickets for family outing',                       'manual', 'approved', ARRAY['family','weekend']),
  ('7866c082-08d5-495f-83fc-212fcf7068ca', '4547e538-d338-474a-881e-be570525fd57', '2026-04-05', 3500.00, 'Education',         'Monthly tuition fee payment',                           'manual', 'approved', ARRAY['recurring','education']),
  ('7866c082-08d5-495f-83fc-212fcf7068ca', '4547e538-d338-474a-881e-be570525fd57', '2026-04-07', 1200.00, 'Personal Care',     'Salon and grooming session',                            'manual', 'approved', ARRAY['self-care']),
  ('7866c082-08d5-495f-83fc-212fcf7068ca', '4547e538-d338-474a-881e-be570525fd57', '2026-04-10', 5800.00, 'Physical Wellness', 'Gym membership renewal quarterly',                      'manual', 'approved', ARRAY['health','quarterly']),
  ('7866c082-08d5-495f-83fc-212fcf7068ca', '4547e538-d338-474a-881e-be570525fd57', '2026-04-12',  750.00, 'Convenience Food',  'Swiggy and Zomato orders this week',                    'manual', 'approved', ARRAY['food','delivery']),
  ('7866c082-08d5-495f-83fc-212fcf7068ca', '4547e538-d338-474a-881e-be570525fd57', '2026-04-15', 4200.00, 'Senior Care',       'Medicines and health supplements for parents',          'manual', 'approved', ARRAY['parents','health']),
  ('7866c082-08d5-495f-83fc-212fcf7068ca', '4547e538-d338-474a-881e-be570525fd57', '2026-04-18', 1850.00, 'Pet Care',          'Vet checkup and dog food supplies',                     'manual', 'approved', ARRAY['pet','monthly']),
  ('7866c082-08d5-495f-83fc-212fcf7068ca', '4547e538-d338-474a-881e-be570525fd57', '2026-04-22', 6500.00, 'Vacation',          'Weekend getaway hotel booking Lonavala',                'manual', 'approved', ARRAY['travel','weekend']),
  ('7866c082-08d5-495f-83fc-212fcf7068ca', '4547e538-d338-474a-881e-be570525fd57', '2026-04-25', 2100.00, 'Mental Wellness',   'Therapy session and mindfulness app subscription',      'manual', 'approved', ARRAY['mental-health','subscription']);
