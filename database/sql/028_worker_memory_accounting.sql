-- Worker memory commitments: base/resident/task_peak/transfer (Architecture v2 §16, §19, A04, T04).

BEGIN;

CREATE TABLE IF NOT EXISTS public.worker_memory_commitments (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_device_id uuid NOT NULL,
  commitment_kind varchar(16) NOT NULL
    CONSTRAINT CK_worker_memory_commitments_kind
    CHECK (commitment_kind IN ('base', 'resident', 'task_peak', 'transfer')),
  commitment_key varchar(128) NOT NULL,
  resident_identity varchar(128) NULL,
  memory_bytes bigint NOT NULL DEFAULT 0
    CONSTRAINT CK_worker_memory_commitments_memory CHECK (memory_bytes >= 0),
  peak_memory_bytes bigint NOT NULL DEFAULT 0
    CONSTRAINT CK_worker_memory_commitments_peak CHECK (peak_memory_bytes >= 0),
  assignment_id uuid NULL,
  model_version_id uuid NULL,
  status varchar(16) NOT NULL DEFAULT 'active'
    CONSTRAINT CK_worker_memory_commitments_status
    CHECK (status IN ('active', 'released')),
  snapshot_sequence bigint NOT NULL DEFAULT 1
    CONSTRAINT CK_worker_memory_commitments_snapshot CHECK (snapshot_sequence > 0),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  released_at_utc timestamptz NULL,
  CONSTRAINT FK_worker_memory_commitments_device
    FOREIGN KEY (worker_device_id) REFERENCES public.worker_devices (id),
  CONSTRAINT UQ_worker_memory_commitments_identity
    UNIQUE (worker_device_id, commitment_kind, commitment_key)
);

CREATE INDEX IF NOT EXISTS IX_worker_memory_commitments_device_active
  ON public.worker_memory_commitments (worker_device_id, commitment_kind, status);

CREATE OR REPLACE FUNCTION public.upsert_worker_memory_commitment(
  p_worker_device_id uuid,
  p_commitment_kind text,
  p_commitment_key text,
  p_resident_identity text,
  p_memory_bytes bigint,
  p_peak_memory_bytes bigint,
  p_assignment_id uuid DEFAULT NULL,
  p_model_version_id uuid DEFAULT NULL,
  p_snapshot_sequence bigint DEFAULT 1
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_commitment_kind NOT IN ('base', 'resident', 'task_peak', 'transfer') THEN
    RAISE EXCEPTION 'MEMORY_COMMITMENT_KIND_INVALID';
  END IF;
  IF p_memory_bytes < 0 OR p_peak_memory_bytes < 0 OR p_snapshot_sequence <= 0 THEN
    RAISE EXCEPTION 'MEMORY_COMMITMENT_ARGUMENT_INVALID';
  END IF;

  INSERT INTO public.worker_memory_commitments(
    worker_device_id, commitment_kind, commitment_key, resident_identity,
    memory_bytes, peak_memory_bytes, assignment_id, model_version_id,
    status, snapshot_sequence
  )
  VALUES (
    p_worker_device_id, p_commitment_kind, p_commitment_key, p_resident_identity,
    p_memory_bytes, p_peak_memory_bytes, p_assignment_id, p_model_version_id,
    'active', p_snapshot_sequence
  )
  ON CONFLICT (worker_device_id, commitment_kind, commitment_key) DO UPDATE
  SET memory_bytes = EXCLUDED.memory_bytes,
      peak_memory_bytes = GREATEST(
        public.worker_memory_commitments.peak_memory_bytes,
        EXCLUDED.peak_memory_bytes
      ),
      resident_identity = COALESCE(EXCLUDED.resident_identity, public.worker_memory_commitments.resident_identity),
      assignment_id = COALESCE(EXCLUDED.assignment_id, public.worker_memory_commitments.assignment_id),
      model_version_id = COALESCE(EXCLUDED.model_version_id, public.worker_memory_commitments.model_version_id),
      status = 'active',
      snapshot_sequence = GREATEST(
        public.worker_memory_commitments.snapshot_sequence,
        EXCLUDED.snapshot_sequence
      ),
      released_at_utc = NULL,
      updated_at_utc = CURRENT_TIMESTAMP
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_worker_memory_commitment_by_assignment(
  p_assignment_id uuid,
  p_commitment_kind text DEFAULT 'task_peak'
) RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated int;
BEGIN
  IF p_commitment_kind NOT IN ('task_peak', 'transfer') THEN
    RAISE EXCEPTION 'MEMORY_COMMITMENT_KIND_INVALID';
  END IF;

  UPDATE public.worker_memory_commitments
  SET status = 'released',
      released_at_utc = CURRENT_TIMESTAMP,
      updated_at_utc = CURRENT_TIMESTAMP
  WHERE assignment_id = p_assignment_id
    AND commitment_kind = p_commitment_kind
    AND status = 'active';

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$$;

COMMENT ON TABLE public.worker_memory_commitments IS
  'Distinct memory accounting basis: base/resident/task_peak/transfer (v2 §16, §19).';

COMMENT ON FUNCTION public.upsert_worker_memory_commitment IS
  'Upsert active memory commitment; resident identity deduped by commitment_key.';

COMMIT;
