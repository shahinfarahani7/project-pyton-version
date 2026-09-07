BEGIN;

CREATE TABLE IF NOT EXISTS public.worker_contribution_opt_in_events (
  id uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id uuid NOT NULL,
  contribution_mode_id varchar(32) NOT NULL,
  opt_in_confirmed boolean NOT NULL,
  occurred_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  request_id varchar(128) NULL,
  CONSTRAINT FK_worker_contribution_opt_in_events_worker
    FOREIGN KEY (worker_id) REFERENCES public.workers(id)
);

CREATE INDEX IF NOT EXISTS IX_worker_contribution_opt_in_events_worker_time
  ON public.worker_contribution_opt_in_events (worker_id, occurred_at_utc DESC);

GRANT SELECT, INSERT ON public.worker_contribution_opt_in_events TO edgemint_runtime;

COMMIT;
