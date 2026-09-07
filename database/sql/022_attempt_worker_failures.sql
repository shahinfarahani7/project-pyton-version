BEGIN;

CREATE TABLE IF NOT EXISTS public.attempt_worker_failures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_attempt_id uuid NOT NULL,
  worker_device_id uuid NOT NULL,
  runtime_class varchar(64) NULL,
  model_version_id varchar(128) NULL,
  failure_code varchar(64) NOT NULL,
  observed_at_utc timestamptz NOT NULL,
  cooldown_until_utc timestamptz NULL,
  CONSTRAINT FK_attempt_worker_failures_attempt
    FOREIGN KEY(task_attempt_id) REFERENCES public.task_attempts(id),
  CONSTRAINT FK_attempt_worker_failures_device
    FOREIGN KEY(worker_device_id) REFERENCES public.worker_devices(id)
);

CREATE INDEX IF NOT EXISTS ix_attempt_worker_failures_attempt
  ON public.attempt_worker_failures(task_attempt_id, observed_at_utc DESC);

CREATE INDEX IF NOT EXISTS ix_attempt_worker_failures_device_cooldown
  ON public.attempt_worker_failures(worker_device_id, cooldown_until_utc DESC);

COMMIT;
