BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS ux_results_assignment
  ON public.results(assignment_id);

CREATE INDEX IF NOT EXISTS ix_results_pending_verification
  ON public.results(status, created_at_utc)
  WHERE status = 'pending_verification';

COMMIT;
