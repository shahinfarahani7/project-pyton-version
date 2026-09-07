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
BEGIN
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
  'Architecture §20 atomic boundary: assignment lease + resource reservation commit or roll back together.';

GRANT EXECUTE ON FUNCTION public.atomic_acquire_assignment_with_reservation(
  uuid, uuid, uuid, text, bytea, integer, integer, integer, integer, integer,
  bigint, bigint, bigint, bigint, bigint, text
) TO edgemint_runtime;

COMMIT;
