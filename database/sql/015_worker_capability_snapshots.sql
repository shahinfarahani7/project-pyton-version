BEGIN;

ALTER TABLE public.worker_devices
  ADD COLUMN IF NOT EXISTS capability_snapshot_json jsonb NULL;

ALTER TABLE public.worker_heartbeats
  ADD COLUMN IF NOT EXISTS capability_snapshot_json jsonb NULL;

ALTER TABLE public.worker_devices
  ADD CONSTRAINT CK_worker_devices_capability_snapshot_json
  CHECK (
    capability_snapshot_json IS NULL
    OR jsonb_typeof(capability_snapshot_json) = 'object'
  );

ALTER TABLE public.worker_heartbeats
  ADD CONSTRAINT CK_worker_heartbeats_capability_snapshot_json
  CHECK (
    capability_snapshot_json IS NULL
    OR jsonb_typeof(capability_snapshot_json) = 'object'
  );

COMMIT;
