-- Add new staff roles: customer_service, reader, billing_service
-- Drop the old CHECK constraint and add a new one with expanded roles

ALTER TABLE app.users DROP CONSTRAINT IF EXISTS users_staff_role_check;

ALTER TABLE app.users ADD CONSTRAINT users_staff_role_check
  CHECK (staff_role IN ('super_admin', 'admin', 'support_staff', 'customer_service', 'reader', 'billing_service'));
