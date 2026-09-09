-- Physical release state independent of logical reservation (Architecture v2 §19, §47, A02, T02).

BEGIN;

ALTER TABLE public.worker_resource_reservations
  ADD COLUMN IF NOT EXISTS physical_release_state varchar(16) NOT NULL DEFAULT 'held'
    CONSTRAINT CK_worker_resource_reservations_physical_release_state
    CHECK (physical_release_state IN ('held', 'stop_requested', 'unknown', 'released')),
  ADD COLUMN IF NOT EXISTS stop_requested_at_utc timestamptz NULL,
  ADD COLUMN IF NOT EXISTS stop_confirmed_at_utc timestamptz NULL,
  ADD COLUMN IF NOT EXISTS physical_release_proof text NULL,
  ADD COLUMN IF NOT EXISTS physical_release_reason text NULL;

CREATE INDEX IF NOT EXISTS IX_worker_resource_reservations_physical_hold
  ON public.worker_resource_reservations (worker_device_id, physical_release_state, exclusive_group)
  WHERE physical_release_state IN ('held', 'stop_requested', 'unknown');

CREATE OR REPLACE FUNCTION public.request_worker_physical_stop(
  p_reservation_id uuid,
  p_fence_token bigint,
  p_reason text DEFAULT 'logical_release'
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.worker_resource_reservations
  SET physical_release_state = 'stop_requested',
      stop_requested_at_utc = COALESCE(stop_requested_at_utc, CURRENT_TIMESTAMP),
      physical_release_reason = COALESCE(p_reason, physical_release_reason),
      updated_at_utc = CURRENT_TIMESTAMP
  WHERE id = p_reservation_id
    AND fence_token = p_fence_token
    AND physical_release_state IN ('held', 'unknown')
    AND status IN ('reserved', 'active', 'released', 'expired', 'revoked');

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 1 THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.worker_resource_reservations
    WHERE id = p_reservation_id
      AND fence_token = p_fence_token
      AND physical_release_state IN ('stop_requested', 'released')
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_worker_physical_release(
  p_reservation_id uuid,
  p_fence_token bigint,
  p_proof text,
  p_reason text DEFAULT 'worker_stop_confirmed'
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated integer;
BEGIN
  IF COALESCE(trim(p_proof), '') = '' THEN
    RAISE EXCEPTION 'PHYSICAL_RELEASE_PROOF_REQUIRED';
  END IF;

  UPDATE public.worker_resource_reservations
  SET physical_release_state = 'released',
      stop_confirmed_at_utc = CURRENT_TIMESTAMP,
      physical_release_proof = p_proof,
      physical_release_reason = COALESCE(p_reason, physical_release_reason),
      updated_at_utc = CURRENT_TIMESTAMP
  WHERE id = p_reservation_id
    AND fence_token = p_fence_token
    AND physical_release_state IN ('held', 'stop_requested', 'unknown');

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 1 THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.worker_resource_reservations
    WHERE id = p_reservation_id
      AND fence_token = p_fence_token
      AND physical_release_state = 'released'
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_worker_physical_release_by_assignment(
  p_assignment_id uuid,
  p_fence_token bigint,
  p_proof text,
  p_reason text DEFAULT 'worker_stop_confirmed'
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_reservation_id uuid;
BEGIN
  SELECT id
  INTO v_reservation_id
  FROM public.worker_resource_reservations
  WHERE assignment_id = p_assignment_id
  ORDER BY reserved_at_utc DESC
  LIMIT 1
  FOR UPDATE;

  IF v_reservation_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN public.confirm_worker_physical_release(
    v_reservation_id,
    p_fence_token,
    p_proof,
    p_reason
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.release_worker_resource_reservation(
  p_reservation_id uuid,
  p_terminal_status text DEFAULT 'released'
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated integer;
  v_status text;
  v_prior_status text;
BEGIN
  IF p_terminal_status NOT IN ('released', 'expired', 'revoked') THEN
    RAISE EXCEPTION 'RESOURCE_RESERVATION_TERMINAL_STATUS_INVALID';
  END IF;

  SELECT status
  INTO v_prior_status
  FROM public.worker_resource_reservations
  WHERE id = p_reservation_id
  FOR UPDATE;

  IF v_prior_status IS NULL THEN
    RAISE EXCEPTION 'RESOURCE_RESERVATION_NOT_FOUND';
  END IF;

  UPDATE public.worker_resource_reservations
  SET status = p_terminal_status,
      released_at_utc = CURRENT_TIMESTAMP,
      updated_at_utc = CURRENT_TIMESTAMP,
      physical_release_state = CASE
        WHEN v_prior_status = 'reserved' THEN 'released'
        WHEN v_prior_status = 'active' THEN 'stop_requested'
        ELSE physical_release_state
      END,
      stop_requested_at_utc = CASE
        WHEN v_prior_status = 'active' THEN COALESCE(stop_requested_at_utc, CURRENT_TIMESTAMP)
        ELSE stop_requested_at_utc
      END,
      stop_confirmed_at_utc = CASE
        WHEN v_prior_status = 'reserved' THEN CURRENT_TIMESTAMP
        ELSE stop_confirmed_at_utc
      END,
      physical_release_proof = CASE
        WHEN v_prior_status = 'reserved' THEN COALESCE(physical_release_proof, 'never_started')
        ELSE physical_release_proof
      END,
      physical_release_reason = CASE
        WHEN v_prior_status = 'reserved' THEN COALESCE(physical_release_reason, 'never_started')
        WHEN v_prior_status = 'active' THEN COALESCE(physical_release_reason, 'logical_release_active')
        ELSE physical_release_reason
      END
  WHERE id = p_reservation_id
    AND status IN ('reserved', 'active');

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 1 THEN
    RETURN true;
  END IF;

  SELECT status INTO v_status
  FROM public.worker_resource_reservations
  WHERE id = p_reservation_id;

  RETURN v_status IN ('released', 'expired', 'revoked');
END;
$$;

CREATE OR REPLACE FUNCTION public.worker_device_resource_totals(
  p_worker_device_id uuid
) RETURNS TABLE(
  cpu_units bigint,
  memory_bytes bigint,
  storage_bytes bigint,
  accelerator_units bigint,
  model_session_units bigint
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    COALESCE(SUM(reservation.cpu_units), 0)::bigint,
    COALESCE(SUM(reservation.memory_bytes), 0)::bigint,
    COALESCE(SUM(reservation.storage_bytes), 0)::bigint,
    COALESCE(SUM(reservation.accelerator_units), 0)::bigint,
    COALESCE(SUM(reservation.model_session_units), 0)::bigint
  FROM public.worker_resource_reservations AS reservation
  WHERE reservation.worker_device_id = p_worker_device_id
    AND (
      reservation.status IN ('reserved', 'active')
      OR (
        reservation.status IN ('released', 'expired', 'revoked')
        AND reservation.physical_release_state IN ('held', 'stop_requested', 'unknown')
      )
    );
$$;

COMMENT ON COLUMN public.worker_resource_reservations.physical_release_state IS
  'Independent physical capacity hold (v2 §19): held/stop_requested/unknown/released.';

COMMENT ON FUNCTION public.confirm_worker_physical_release IS
  'Worker-reported stop confirmation; first valid proof wins (v2 §47).';

COMMIT;
