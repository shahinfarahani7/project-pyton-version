BEGIN;

ALTER TABLE public.worker_devices
  ADD COLUMN IF NOT EXISTS installation_id varchar(128) NULL,
  ADD COLUMN IF NOT EXISTS public_key_fingerprint char(64) NULL;

CREATE UNIQUE INDEX IF NOT EXISTS UQ_worker_devices_installation
  ON public.worker_devices (installation_id)
  WHERE installation_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS UQ_worker_devices_public_key_fingerprint
  ON public.worker_devices (public_key_fingerprint)
  WHERE public_key_fingerprint IS NOT NULL;

ALTER TABLE public.device_challenges
  ADD COLUMN IF NOT EXISTS installation_id varchar(128) NULL;

CREATE INDEX IF NOT EXISTS IX_device_challenges_installation_open
  ON public.device_challenges (installation_id)
  WHERE used_at_utc IS NULL;

COMMIT;
