-- CPU contribution enforcement certification (Architecture v2 §16.1, §17, A06, T06).

CREATE TABLE IF NOT EXISTS public.worker_cpu_enforcement_certifications (
  worker_device_id uuid NOT NULL PRIMARY KEY,
  policy_ref varchar(128) NOT NULL,
  measurement_window_ms int NOT NULL
    CONSTRAINT CK_worker_cpu_enforcement_window CHECK (measurement_window_ms > 0),
  covered_process_scope varchar(64) NOT NULL,
  tolerated_burst_bps int NOT NULL
    CONSTRAINT CK_worker_cpu_enforcement_burst CHECK (tolerated_burst_bps >= 0),
  control_stop_reaction_bound_ms int NOT NULL
    CONSTRAINT CK_worker_cpu_enforcement_stop CHECK (control_stop_reaction_bound_ms > 0),
  enforcement_mechanism varchar(64) NOT NULL,
  approved_percent int NOT NULL
    CONSTRAINT CK_worker_cpu_enforcement_percent CHECK (approved_percent BETWEEN 1 AND 100),
  contribution_mode_id varchar(32) NOT NULL,
  last_observed_cpu_usage_bps int NULL
    CONSTRAINT CK_worker_cpu_enforcement_observed CHECK (
      last_observed_cpu_usage_bps IS NULL
      OR last_observed_cpu_usage_bps BETWEEN 0 AND 10000
    ),
  snapshot_sequence bigint NOT NULL DEFAULT 1
    CONSTRAINT CK_worker_cpu_enforcement_snapshot CHECK (snapshot_sequence > 0),
  certified_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_worker_cpu_enforcement_device
    FOREIGN KEY (worker_device_id) REFERENCES public.worker_devices (id)
);

CREATE INDEX IF NOT EXISTS IX_worker_cpu_enforcement_policy
  ON public.worker_cpu_enforcement_certifications (policy_ref, updated_at_utc DESC);

CREATE OR REPLACE FUNCTION public.upsert_worker_cpu_enforcement_certification(
  p_worker_device_id uuid,
  p_policy_ref text,
  p_measurement_window_ms int,
  p_covered_process_scope text,
  p_tolerated_burst_bps int,
  p_control_stop_reaction_bound_ms int,
  p_enforcement_mechanism text,
  p_approved_percent int,
  p_contribution_mode_id text,
  p_last_observed_cpu_usage_bps int DEFAULT NULL,
  p_snapshot_sequence bigint DEFAULT 1
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_measurement_window_ms <= 0
     OR p_control_stop_reaction_bound_ms <= 0
     OR p_tolerated_burst_bps < 0
     OR p_approved_percent NOT BETWEEN 1 AND 100
     OR p_snapshot_sequence <= 0 THEN
    RAISE EXCEPTION 'CPU_ENFORCEMENT_ARGUMENT_INVALID';
  END IF;

  INSERT INTO public.worker_cpu_enforcement_certifications(
    worker_device_id, policy_ref, measurement_window_ms, covered_process_scope,
    tolerated_burst_bps, control_stop_reaction_bound_ms, enforcement_mechanism,
    approved_percent, contribution_mode_id, last_observed_cpu_usage_bps,
    snapshot_sequence
  )
  VALUES (
    p_worker_device_id, p_policy_ref, p_measurement_window_ms, p_covered_process_scope,
    p_tolerated_burst_bps, p_control_stop_reaction_bound_ms, p_enforcement_mechanism,
    p_approved_percent, p_contribution_mode_id, p_last_observed_cpu_usage_bps,
    p_snapshot_sequence
  )
  ON CONFLICT (worker_device_id) DO UPDATE
  SET policy_ref = EXCLUDED.policy_ref,
      measurement_window_ms = EXCLUDED.measurement_window_ms,
      covered_process_scope = EXCLUDED.covered_process_scope,
      tolerated_burst_bps = EXCLUDED.tolerated_burst_bps,
      control_stop_reaction_bound_ms = EXCLUDED.control_stop_reaction_bound_ms,
      enforcement_mechanism = EXCLUDED.enforcement_mechanism,
      approved_percent = EXCLUDED.approved_percent,
      contribution_mode_id = EXCLUDED.contribution_mode_id,
      last_observed_cpu_usage_bps = COALESCE(
        EXCLUDED.last_observed_cpu_usage_bps,
        public.worker_cpu_enforcement_certifications.last_observed_cpu_usage_bps
      ),
      snapshot_sequence = GREATEST(
        public.worker_cpu_enforcement_certifications.snapshot_sequence,
        EXCLUDED.snapshot_sequence
      ),
      updated_at_utc = CURRENT_TIMESTAMP
  RETURNING worker_device_id INTO v_id;

  RETURN v_id;
END;
$$;

COMMENT ON TABLE public.worker_cpu_enforcement_certifications IS
  'Windowed CPU contribution enforcement certification per device (v2 §16.1).';

COMMENT ON FUNCTION public.upsert_worker_cpu_enforcement_certification IS
  'Upsert active CPU enforcement certification from heartbeat/policy sync.';
