BEGIN;

ALTER TABLE public.worker_heartbeats
  ADD COLUMN IF NOT EXISTS telemetry_json jsonb NULL;

ALTER TABLE public.worker_heartbeats
  ADD CONSTRAINT CK_worker_heartbeats_telemetry_json
  CHECK (
    telemetry_json IS NULL
    OR jsonb_typeof(telemetry_json) = 'object'
  );

COMMIT;
