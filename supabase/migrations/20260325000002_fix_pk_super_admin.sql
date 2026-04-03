-- One-time fix: Promote pk@myparivaar.com to super_admin
-- The approval auto-execution was not in place when the original request was approved
UPDATE app.users
SET staff_role = 'super_admin',
    staff_scope = 'global',
    role = 'super_admin'
WHERE email = 'pk@myparivaar.com'
  AND deleted_at IS NULL;
