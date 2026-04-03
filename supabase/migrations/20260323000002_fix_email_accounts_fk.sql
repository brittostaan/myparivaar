-- Fix foreign key constraints on public.email_accounts.
-- The original migration (20260311000004) created FKs pointing at
-- public.households and public.users which do not exist — the real
-- tables live in the "app" schema.  This migration drops the broken
-- constraints and recreates them correctly.

-- 1. Drop any existing FK constraints on household_id and user_id
--    (constraint names may vary; use information_schema to be safe)
DO $$
DECLARE
  _con RECORD;
BEGIN
  FOR _con IN
    SELECT conname
      FROM pg_constraint
     WHERE conrelid = 'public.email_accounts'::regclass
       AND contype  = 'f'                       -- foreign key
       AND (
             conname ILIKE '%household%'
          OR conname ILIKE '%user%'
       )
  LOOP
    EXECUTE format('ALTER TABLE public.email_accounts DROP CONSTRAINT %I', _con.conname);
    RAISE NOTICE 'Dropped FK constraint: %', _con.conname;
  END LOOP;
END
$$;

-- 2. Re-add correct FK constraints pointing to app schema
ALTER TABLE public.email_accounts
  ADD CONSTRAINT email_accounts_household_id_fkey
    FOREIGN KEY (household_id) REFERENCES app.households(id) ON DELETE CASCADE;

ALTER TABLE public.email_accounts
  ADD CONSTRAINT email_accounts_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES app.users(id) ON DELETE CASCADE;
