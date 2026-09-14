-- Worker row lock and capacity recheck before reservation (audit F12).

BEGIN;

CREATE OR REPLACE FUNCTION public.atomic_acquire_assignment_with_reservation(
  p_task_attempt_id uuid,
  p_worker_id uuid,
  p_worker_device_id uuid,
  p_router_instance_id text,
  p_lease_token_hash bytea,
  p_lease_seconds integer,
  p_delivery_seconds integer,
  p_auto_start_grace_seconds integer,
  p_heartbeat_max_age_seconds integer,
  p_min_trust_bps integer,
  p_cpu_units bigint,
  p_memory_bytes bigint,
  p_storage_bytes bigint,
  p_accelerator_units bigint,
  p_model_session_units bigint,
  p_exclusive_group text
) RETURNS TABLE(
  assignment_id uuid,
  fence_token bigint,
  lease_expires_at_utc timestamptz,
  reservation_id uuid
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_assignment_id uuid;
  v_fence_token bigint;
  v_lease_expires_at_utc timestamptz;
  v_workspace_id uuid;
  v_task_revision_id uuid;
  v_reservation_id uuid;
  v_device_tier varchar(8);
  v_capacity integer;
  v_active_leases integer;
  v_reserved_cpu bigint;
  v_reserved_memory bigint;
  v_reserved_storage bigint;
  v_reserved_sessions bigint;
  v_exclusive_active integer;
BEGIN
  PERFORM 1
  FROM public.workers AS worker
  WHERE worker.id = p_worker_id
    AND worker.status = 'active'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'WORKER_NOT_ELIGIBLE';
  END IF;

  SELECT device.device_tier
  INTO v_device_tier
  FROM public.worker_devices AS device
  WHERE device.id = p_worker_device_id
    AND device.worker_id = p_worker_id
    AND device.status = 'active'
  FOR UPDATE;

  IF v_device_tier IS NULL THEN
    RAISE EXCEPTION 'WORKER_NOT_ELIGIBLE';
  END IF;

  v_capacity := CASE WHEN v_device_tier = 'T4' THEN 2 ELSE 1 END;
  SELECT count(*)
  INTO v_active_leases
  FROM public.assignments
  WHERE worker_device_id = p_worker_device_id
    AND status IN ('leased', 'running')
    AND lease_expires_at_utc > CURRENT_TIMESTAMP;

  IF v_active_leases >= v_capacity THEN
    RAISE EXCEPTION 'WORKER_CAPACITY_EXHAUSTED';
  END IF;

  SELECT
    COALESCE(sum(reservation.cpu_units), 0),
    COALESCE(sum(reservation.memory_bytes), 0),
    COALESCE(sum(reservation.storage_bytes), 0),
    COALESCE(sum(reservation.model_session_units), 0)
  INTO v_reserved_cpu, v_reserved_memory, v_reserved_storage, v_reserved_sessions
  FROM public.worker_resource_reservations AS reservation
  WHERE reservation.worker_device_id = p_worker_device_id
    AND reservation.status IN ('reserved', 'active')
    AND reservation.expires_at_utc > CURRENT_TIMESTAMP;

  IF p_cpu_units > 0 AND v_reserved_cpu + p_cpu_units > 2147483647 THEN
    RAISE EXCEPTION 'CPU_BUDGET_EXCEEDED';
  END IF;
  IF p_memory_bytes > 0 AND v_reserved_memory + p_memory_bytes > 9223372036854775807 THEN
    RAISE EXCEPTION 'MEMORY_BUDGET_EXCEEDED';
  END IF;
  IF p_storage_bytes > 0 AND v_reserved_storage + p_storage_bytes > 9223372036854775807 THEN
    RAISE EXCEPTION 'STORAGE_BUDGET_EXCEEDED';
  END IF;
  IF p_model_session_units > 0 AND v_reserved_sessions + p_model_session_units > 2147483647 THEN
    RAISE EXCEPTION 'WORKER_CAPACITY_EXHAUSTED';
  END IF;

  IF COALESCE(p_exclusive_group, '') <> '' THEN
    SELECT count(*)
    INTO v_exclusive_active
    FROM public.worker_resource_reservations AS reservation
    WHERE reservation.worker_device_id = p_worker_device_id
      AND reservation.status IN ('reserved', 'active')
      AND reservation.expires_at_utc > CURRENT_TIMESTAMP
      AND reservation.exclusive_group = p_exclusive_group;

    IF v_exclusive_active > 0 THEN
      RAISE EXCEPTION 'EXCLUSIVE_GROUP_SATURATED';
    END IF;
  END IF;

  SELECT lease.assignment_id, lease.fence_token, lease.lease_expires_at_utc
  INTO v_assignment_id, v_fence_token, v_lease_expires_at_utc
  FROM public.acquire_assignment_lease(
    p_task_attempt_id, p_worker_id, p_worker_device_id, p_router_instance_id,
    p_lease_token_hash, p_lease_seconds, p_delivery_seconds,
    p_auto_start_grace_seconds, p_heartbeat_max_age_seconds, p_min_trust_bps
  ) AS lease;

  IF v_assignment_id IS NULL THEN
    RAISE EXCEPTION 'WORKER_NOT_ELIGIBLE';
  END IF;

  SELECT assignment.workspace_id, revision.id
  INTO v_workspace_id, v_task_revision_id
  FROM public.assignments AS assignment
  JOIN public.task_attempts AS attempt
    ON attempt.id = assignment.task_attempt_id
   AND attempt.workspace_id = assignment.workspace_id
  JOIN public.tasks AS task
    ON task.id = attempt.task_id
   AND task.workspace_id = attempt.workspace_id
  JOIN public.task_revisions AS revision
    ON revision.id = task.current_revision_id
   AND revision.workspace_id = task.workspace_id
  WHERE assignment.id = v_assignment_id;

  IF v_workspace_id IS NULL OR v_task_revision_id IS NULL THEN
    RAISE EXCEPTION 'ASSIGNMENT_CONTEXT_INVALID';
  END IF;

  v_reservation_id := public.create_worker_resource_reservation(
    v_workspace_id,
    v_assignment_id,
    p_worker_device_id,
    v_task_revision_id,
    p_cpu_units,
    p_memory_bytes,
    p_storage_bytes,
    p_accelerator_units,
    p_model_session_units,
    p_exclusive_group,
    v_fence_token,
    v_lease_expires_at_utc
  );

  RETURN QUERY
  SELECT v_assignment_id, v_fence_token, v_lease_expires_at_utc, v_reservation_id;
END
$$;

COMMENT ON FUNCTION public.atomic_acquire_assignment_with_reservation IS
  'Section 20 atomic boundary with worker lock + reservation recheck before side effects.';

COMMIT;
