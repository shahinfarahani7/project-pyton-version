BEGIN;

CREATE TABLE IF NOT EXISTS public.worker_resource_reservations (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  worker_device_id uuid NOT NULL,
  task_revision_id uuid NOT NULL,
  cpu_units bigint NOT NULL DEFAULT 0
    CONSTRAINT CK_worker_resource_reservations_cpu CHECK (cpu_units >= 0),
  memory_bytes bigint NOT NULL DEFAULT 0
    CONSTRAINT CK_worker_resource_reservations_memory CHECK (memory_bytes >= 0),
  storage_bytes bigint NOT NULL DEFAULT 0
    CONSTRAINT CK_worker_resource_reservations_storage CHECK (storage_bytes >= 0),
  accelerator_units bigint NOT NULL DEFAULT 0
    CONSTRAINT CK_worker_resource_reservations_accelerator CHECK (accelerator_units >= 0),
  model_session_units bigint NOT NULL DEFAULT 0
    CONSTRAINT CK_worker_resource_reservations_model_session CHECK (model_session_units >= 0),
  exclusive_group varchar(64) NOT NULL DEFAULT '',
  status varchar(16) NOT NULL
    CONSTRAINT CK_worker_resource_reservations_status
    CHECK (status IN ('reserved', 'active', 'released', 'expired', 'revoked')),
  fence_token bigint NOT NULL CONSTRAINT CK_worker_resource_reservations_fence CHECK (fence_token > 0),
  reserved_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  activated_at_utc timestamptz NULL,
  released_at_utc timestamptz NULL,
  expires_at_utc timestamptz NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_worker_resource_reservations_workspace
    FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id),
  CONSTRAINT FK_worker_resource_reservations_assignment_scope
    FOREIGN KEY (assignment_id, workspace_id) REFERENCES public.assignments(id, workspace_id),
  CONSTRAINT FK_worker_resource_reservations_device
    FOREIGN KEY (worker_device_id) REFERENCES public.worker_devices(id),
  CONSTRAINT FK_worker_resource_reservations_revision_scope
    FOREIGN KEY (task_revision_id, workspace_id) REFERENCES public.task_revisions(id, workspace_id),
  CONSTRAINT CK_worker_resource_reservations_resource_vector
    CHECK (
      cpu_units > 0
      OR memory_bytes > 0
      OR storage_bytes > 0
      OR accelerator_units > 0
      OR model_session_units > 0
    ),
  CONSTRAINT CK_worker_resource_reservations_activation_window
    CHECK (
      (status = 'active' AND activated_at_utc IS NOT NULL)
      OR (status <> 'active' AND activated_at_utc IS NULL)
      OR status IN ('released', 'expired', 'revoked')
    ),
  CONSTRAINT CK_worker_resource_reservations_release_window
    CHECK (
      (status IN ('released', 'expired', 'revoked') AND released_at_utc IS NOT NULL)
      OR (status IN ('reserved', 'active') AND released_at_utc IS NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS UX_worker_resource_reservations_open_assignment
  ON public.worker_resource_reservations (assignment_id)
  WHERE status IN ('reserved', 'active');

CREATE INDEX IF NOT EXISTS IX_worker_resource_reservations_device_status
  ON public.worker_resource_reservations (worker_device_id, status);

CREATE INDEX IF NOT EXISTS IX_worker_resource_reservations_expires
  ON public.worker_resource_reservations (expires_at_utc)
  WHERE status IN ('reserved', 'active');

CREATE OR REPLACE FUNCTION public.create_worker_resource_reservation(
  p_workspace_id uuid,
  p_assignment_id uuid,
  p_worker_device_id uuid,
  p_task_revision_id uuid,
  p_cpu_units bigint,
  p_memory_bytes bigint,
  p_storage_bytes bigint,
  p_accelerator_units bigint,
  p_model_session_units bigint,
  p_exclusive_group text,
  p_fence_token bigint,
  p_expires_at_utc timestamptz
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_reservation_id uuid := uuidv7();
BEGIN
  IF p_cpu_units < 0 OR p_memory_bytes < 0 OR p_storage_bytes < 0
     OR p_accelerator_units < 0 OR p_model_session_units < 0 THEN
    RAISE EXCEPTION 'RESOURCE_RESERVATION_ARGUMENT_INVALID';
  END IF;
  IF p_cpu_units = 0 AND p_memory_bytes = 0 AND p_storage_bytes = 0
     AND p_accelerator_units = 0 AND p_model_session_units = 0 THEN
    RAISE EXCEPTION 'RESOURCE_RESERVATION_EMPTY';
  END IF;
  IF p_fence_token <= 0 OR p_expires_at_utc <= CURRENT_TIMESTAMP THEN
    RAISE EXCEPTION 'RESOURCE_RESERVATION_ARGUMENT_INVALID';
  END IF;

  INSERT INTO public.worker_resource_reservations(
    id, workspace_id, assignment_id, worker_device_id, task_revision_id,
    cpu_units, memory_bytes, storage_bytes, accelerator_units, model_session_units,
    exclusive_group, status, fence_token, reserved_at_utc, expires_at_utc
  )
  SELECT
    v_reservation_id, p_workspace_id, p_assignment_id, p_worker_device_id, p_task_revision_id,
    p_cpu_units, p_memory_bytes, p_storage_bytes, p_accelerator_units, p_model_session_units,
    COALESCE(p_exclusive_group, ''), 'reserved', p_fence_token, CURRENT_TIMESTAMP, p_expires_at_utc
  FROM public.assignments AS assignment
  WHERE assignment.id = p_assignment_id
    AND assignment.workspace_id = p_workspace_id
    AND assignment.worker_device_id = p_worker_device_id
    AND assignment.fence_token = p_fence_token
    AND assignment.status IN ('leased', 'running');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RESOURCE_RESERVATION_ASSIGNMENT_INVALID';
  END IF;

  RETURN v_reservation_id;
END
$$;

CREATE OR REPLACE FUNCTION public.activate_worker_resource_reservation(
  p_reservation_id uuid,
  p_fence_token bigint
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.worker_resource_reservations AS reservation
  SET status = 'active',
      activated_at_utc = CURRENT_TIMESTAMP,
      updated_at_utc = CURRENT_TIMESTAMP
  FROM public.assignments AS assignment
  WHERE reservation.id = p_reservation_id
    AND reservation.assignment_id = assignment.id
    AND reservation.workspace_id = assignment.workspace_id
    AND reservation.status = 'reserved'
    AND reservation.fence_token = p_fence_token
    AND assignment.fence_token = p_fence_token
    AND assignment.status = 'running';

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 1 THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.worker_resource_reservations
    WHERE id = p_reservation_id
      AND status = 'active'
      AND fence_token = p_fence_token
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END
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
BEGIN
  IF p_terminal_status NOT IN ('released', 'expired', 'revoked') THEN
    RAISE EXCEPTION 'RESOURCE_RESERVATION_TERMINAL_STATUS_INVALID';
  END IF;

  UPDATE public.worker_resource_reservations
  SET status = p_terminal_status,
      released_at_utc = CURRENT_TIMESTAMP,
      updated_at_utc = CURRENT_TIMESTAMP
  WHERE id = p_reservation_id
    AND status IN ('reserved', 'active');

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 1 THEN
    RETURN true;
  END IF;

  SELECT status INTO v_status
  FROM public.worker_resource_reservations
  WHERE id = p_reservation_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'RESOURCE_RESERVATION_NOT_FOUND';
  END IF;

  RETURN v_status IN ('released', 'expired', 'revoked');
END
$$;

CREATE OR REPLACE FUNCTION public.release_worker_resource_reservation_by_assignment(
  p_assignment_id uuid,
  p_terminal_status text DEFAULT 'released'
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
    AND status IN ('reserved', 'active')
  ORDER BY reserved_at_utc DESC
  LIMIT 1
  FOR UPDATE;

  IF v_reservation_id IS NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.worker_resource_reservations
      WHERE assignment_id = p_assignment_id
        AND status IN ('released', 'expired', 'revoked')
    ) THEN
      RETURN true;
    END IF;
    RETURN false;
  END IF;

  RETURN public.release_worker_resource_reservation(v_reservation_id, p_terminal_status);
END
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
    AND reservation.status IN ('reserved', 'active');
$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.worker_resource_reservations TO edgemint_runtime;
GRANT EXECUTE ON FUNCTION public.create_worker_resource_reservation(
  uuid, uuid, uuid, uuid, bigint, bigint, bigint, bigint, bigint, text, bigint, timestamptz
) TO edgemint_runtime;
GRANT EXECUTE ON FUNCTION public.activate_worker_resource_reservation(uuid, bigint) TO edgemint_runtime;
GRANT EXECUTE ON FUNCTION public.release_worker_resource_reservation(uuid, text) TO edgemint_runtime;
GRANT EXECUTE ON FUNCTION public.release_worker_resource_reservation_by_assignment(uuid, text) TO edgemint_runtime;
GRANT EXECUTE ON FUNCTION public.worker_device_resource_totals(uuid) TO edgemint_runtime;

COMMIT;
