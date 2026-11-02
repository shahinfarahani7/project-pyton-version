-- Dev worker-panel Fibonai points. Integer points, not micro-EUR.
-- One row per device and task so a repeated result upload cannot credit twice.

BEGIN;

CREATE TABLE IF NOT EXISTS public.worker_fibonai_credits (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_device_id uuid NOT NULL,
  task_id varchar(128) NOT NULL,
  points integer NOT NULL CONSTRAINT CK_fibonai_credits_points CHECK (points > 0),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_fibonai_credits_device
    FOREIGN KEY (worker_device_id) REFERENCES public.worker_devices (id),
  CONSTRAINT UQ_fibonai_credits_device_task UNIQUE (worker_device_id, task_id)
);

CREATE INDEX IF NOT EXISTS ix_fibonai_credits_device
  ON public.worker_fibonai_credits (worker_device_id);

COMMIT;
