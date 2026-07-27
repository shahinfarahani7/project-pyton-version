BEGIN;

ALTER TABLE public.quotes
  ADD COLUMN IF NOT EXISTS public_id varchar(32) NULL;

CREATE UNIQUE INDEX IF NOT EXISTS UQ_quotes_public_id ON public.quotes (public_id)
  WHERE public_id IS NOT NULL;

ALTER TABLE public.task_revisions
  ADD COLUMN IF NOT EXISTS public_id varchar(32) NULL;

CREATE UNIQUE INDEX IF NOT EXISTS UQ_task_revisions_public_id ON public.task_revisions (public_id)
  WHERE public_id IS NOT NULL;

ALTER TABLE public.credit_reservations
  ADD COLUMN IF NOT EXISTS task_id uuid NULL,
  ADD COLUMN IF NOT EXISTS task_revision_id uuid NULL,
  ADD COLUMN IF NOT EXISTS expires_at_utc timestamptz NULL;

COMMIT;
