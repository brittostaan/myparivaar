-- Create Devi's Household and Link User
-- Run this in Supabase Dashboard → SQL Editor

-- Create household and update user in one transaction
WITH new_household AS (
  INSERT INTO public.households (name, admin_firebase_uid, plan)
  VALUES ('Devi''s Family', '9eefa45c-71b3-4238-ad47-3af7769ff328', 'free')
  RETURNING id, name
)
UPDATE public.users
SET 
  role = 'admin',
  household_id = (SELECT id FROM new_household),
  display_name = 'Devi'
WHERE email = 'devi@myparivaar.com'
RETURNING 
  id, 
  firebase_uid, 
  email, 
  role, 
  household_id,
  display_name,
  'Successfully created household and updated user' as status;

-- Verify the household was created
SELECT 
  h.id,
  h.name,
  h.admin_firebase_uid,
  h.plan,
  COUNT(u.id) as member_count
FROM public.households h
LEFT JOIN public.users u ON h.id = u.household_id
WHERE h.name = 'Devi''s Family'
GROUP BY h.id, h.name, h.admin_firebase_uid, h.plan;
