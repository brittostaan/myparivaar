-- Add 'admin' as a valid staff_role
ALTER TABLE app.users DROP CONSTRAINT IF EXISTS users_staff_role_check;

ALTER TABLE app.users ADD CONSTRAINT users_staff_role_check
  CHECK (staff_role IN ('super_admin', 'admin', 'support_staff', 'customer_service', 'reader', 'billing_service'));
