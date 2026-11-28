-- Portal operations admins managed from the admin console.
-- Environment bootstrap (EDGEMINT_OPERATIONS_ADMIN_EMAILS) remains authoritative for seeded emails;
-- rows here grant additional (or overriding) portal admin access.

BEGIN;

CREATE TABLE IF NOT EXISTS public.operations_admin_emails (
  email varchar(254) PRIMARY KEY,
  role varchar(64) NOT NULL,
  created_by varchar(254) NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT CK_operations_admin_emails_role CHECK (
    role IN (
      'operator.readonly',
      'operator.standard',
      'operator.approver',
      'operator.break_glass'
    )
  )
);

CREATE INDEX IF NOT EXISTS ix_operations_admin_emails_role
  ON public.operations_admin_emails (role);

COMMIT;
