BEGIN;

CREATE TABLE IF NOT EXISTS public.worker_calibration_profiles (
  worker_device_id uuid NOT NULL PRIMARY KEY,
  suite_version varchar(64) NOT NULL,
  measured_at_utc timestamptz NOT NULL,
  metrics_json jsonb NOT NULL,
  profile_version bigint NOT NULL DEFAULT 1 CONSTRAINT CK_worker_calibration_profiles_version CHECK (profile_version > 0),
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_worker_calibration_profiles_device
    FOREIGN KEY (worker_device_id) REFERENCES public.worker_devices(id),
  CONSTRAINT CK_worker_calibration_profiles_metrics_json
    CHECK (jsonb_typeof(metrics_json) = 'object')
);

CREATE INDEX IF NOT EXISTS IX_worker_calibration_profiles_measured
  ON public.worker_calibration_profiles (measured_at_utc DESC);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.worker_calibration_profiles TO edgemint_runtime;

COMMIT;
