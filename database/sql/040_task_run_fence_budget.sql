-- TaskRun monotonic fence and assignment budget reservation (audit F13).

BEGIN;

CREATE OR REPLACE FUNCTION public.acquire_assignment_lease(
  p_task_attempt_id uuid,
  p_worker_id uuid,
  p_worker_device_id uuid,
  p_router_instance_id text,
  p_lease_token_hash bytea,
  p_lease_seconds integer,
  p_delivery_seconds integer,
  p_auto_start_grace_seconds integer,
  p_heartbeat_max_age_seconds integer,
  p_min_trust_bps integer
) RETURNS TABLE(assignment_id uuid, fence_token bigint, lease_expires_at_utc timestamptz)
LANGUAGE plpgsql
AS $$
DECLARE
  v_assignment_id uuid := uuidv7();
  v_fence_token bigint;
  v_workspace_id uuid;
  v_task_id uuid;
  v_revision_id uuid;
  v_task_run_id uuid;
  v_device_tier varchar(8);
  v_capacity integer;
  v_active_leases integer;
  v_expiry timestamptz := CURRENT_TIMESTAMP + make_interval(secs => p_lease_seconds);
  v_budget_reserved boolean;
BEGIN
  IF p_lease_token_hash IS NULL OR octet_length(p_lease_token_hash) <> 32 THEN
    RAISE EXCEPTION 'LEASE_TOKEN_HASH_INVALID';
  END IF;
  IF p_lease_seconds <= 0 OR p_delivery_seconds <= 0 OR p_auto_start_grace_seconds <= 0
     OR p_heartbeat_max_age_seconds <= 0 OR p_min_trust_bps < 0 THEN
    RAISE EXCEPTION 'ASSIGNMENT_ARGUMENT_INVALID';
  END IF;

  SELECT attempt.workspace_id, attempt.task_id, task.current_revision_id, attempt.task_run_id
  INTO v_workspace_id, v_task_id, v_revision_id, v_task_run_id
  FROM public.task_attempts AS attempt
  JOIN public.tasks AS task
    ON task.id = attempt.task_id AND task.workspace_id = attempt.workspace_id
  WHERE attempt.id = p_task_attempt_id
    AND attempt.status = 'matching'
    AND attempt.routing_claim_owner = p_router_instance_id
    AND attempt.routing_claim_expires_at_utc > CURRENT_TIMESTAMP
    AND task.lifecycle_status IN ('admitted', 'queued')
  FOR UPDATE OF attempt, task;

  IF v_workspace_id IS NULL OR v_revision_id IS NULL THEN
    RAISE EXCEPTION 'ROUTING_CLAIM_INVALID';
  END IF;

  IF v_task_run_id IS NOT NULL THEN
    v_budget_reserved := public.reserve_task_run_budget(v_task_run_id, 'assignment');
    IF NOT COALESCE(v_budget_reserved, false) THEN
      RAISE EXCEPTION 'NO_CAPACITY';
    END IF;
  END IF;

  SELECT device.device_tier
  INTO v_device_tier
  FROM public.workers AS worker
  JOIN public.worker_devices AS device
    ON device.worker_id = worker.id
  JOIN public.worker_preferences AS preference
    ON preference.worker_id = worker.id
  JOIN LATERAL (
    SELECT heartbeat.*
    FROM public.worker_heartbeats AS heartbeat
    WHERE heartbeat.worker_device_id = device.id
    ORDER BY heartbeat.received_at_utc DESC, heartbeat.sequence_number DESC
    LIMIT 1
  ) AS heartbeat ON true
  JOIN public.task_revisions AS revision
    ON revision.id = v_revision_id AND revision.workspace_id = v_workspace_id
  WHERE worker.id = p_worker_id
    AND device.id = p_worker_device_id
    AND worker.status = 'active'
    AND worker.trust_bps >= p_min_trust_bps
    AND preference.availability = 'available'
    AND (preference.schedule_mode = 'always' OR CURRENT_TIMESTAMP BETWEEN preference.effective_window_start_utc AND preference.effective_window_end_utc)
    AND EXISTS (
      SELECT 1 FROM public.worker_consents AS consent
      WHERE consent.worker_id = worker.id AND consent.withdrawn_at_utc IS NULL
    )
    AND device.status = 'active'
    AND device.attestation_status = 'verified'
    AND device.attestation_expires_at_utc > CURRENT_TIMESTAMP
    AND heartbeat.received_at_utc >= CURRENT_TIMESTAMP - make_interval(secs => p_heartbeat_max_age_seconds)
    AND heartbeat.battery_bps >= preference.minimum_battery_percent * 100
    AND heartbeat.thermal_state IN ('nominal', 'fair')
    AND heartbeat.network_type <> 'offline'
    AND (
      preference.network_policy = 'any_online'
      OR (preference.network_policy = 'wifi_only' AND heartbeat.network_type = 'wifi')
      OR (preference.network_policy = 'unmetered_only' AND heartbeat.network_type IN ('wifi', 'ethernet'))
      OR (preference.network_policy = 'wifi_or_ethernet' AND heartbeat.network_type IN ('wifi', 'ethernet'))
    )
    AND (preference.charging_policy <> 'required' OR heartbeat.charging)
    AND heartbeat.free_ram_bytes >= revision.minimum_free_ram_bytes
    AND heartbeat.free_storage_bytes >= revision.minimum_free_storage_bytes
    AND (revision.required_runtime_abi = 'any' OR revision.required_runtime_abi = device.runtime_abi)
    AND CASE revision.required_device_tier
      WHEN 'T1' THEN device.device_tier IN ('T1', 'T2', 'T3', 'T4')
      WHEN 'T2' THEN device.device_tier IN ('T2', 'T3', 'T4')
      WHEN 'T3' THEN device.device_tier IN ('T3', 'T4')
      WHEN 'T4' THEN device.device_tier = 'T4'
      ELSE false
    END
    AND (
      revision.allowed_worker_regions_json @> '["*"]'::jsonb
      OR revision.allowed_worker_regions_json ? device.region_code
    )
    AND (
      revision.model_version_id IS NULL
      OR EXISTS (
        SELECT 1
        FROM public.device_model_installs AS install
        JOIN public.model_versions AS model_version ON model_version.id = install.model_version_id
        WHERE install.worker_device_id = device.id
          AND install.model_version_id = revision.model_version_id
          AND install.status = 'active'
          AND install.verified_sha256 = model_version.artifact_sha256
          AND model_version.status = 'active'
      )
    )
  FOR UPDATE OF worker, device, preference;

  IF v_device_tier IS NULL THEN
    RAISE EXCEPTION 'WORKER_NOT_ELIGIBLE';
  END IF;

  v_capacity := CASE WHEN v_device_tier = 'T4' THEN 2 ELSE 1 END;
  SELECT count(*) INTO v_active_leases
  FROM public.assignments
  WHERE worker_device_id = p_worker_device_id
    AND status IN ('leased', 'running')
    AND lease_expires_at_utc > CURRENT_TIMESTAMP;

  IF v_active_leases >= v_capacity THEN
    RAISE EXCEPTION 'WORKER_CAPACITY_EXHAUSTED';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_task_attempt_id::text, 0));

  IF v_task_run_id IS NOT NULL THEN
    SELECT COALESCE(max(assignment.fence_token), 0) + 1
    INTO v_fence_token
    FROM public.assignments AS assignment
    JOIN public.task_attempts AS attempt
      ON attempt.id = assignment.task_attempt_id
     AND attempt.workspace_id = assignment.workspace_id
    WHERE attempt.task_run_id = v_task_run_id;
  ELSE
    SELECT COALESCE(max(assignment.fence_token), 0) + 1
    INTO v_fence_token
    FROM public.assignments AS assignment
    WHERE assignment.task_attempt_id = p_task_attempt_id;
  END IF;

  INSERT INTO public.assignments(
    id, workspace_id, task_attempt_id, worker_device_id, status, lease_token_hash,
    fence_token, lease_expires_at_utc, delivery_deadline_at_utc, start_deadline_at_utc,
    assigned_at_utc, created_at_utc
  ) VALUES (
    v_assignment_id, v_workspace_id, p_task_attempt_id, p_worker_device_id, 'leased', p_lease_token_hash,
    v_fence_token, v_expiry,
    CURRENT_TIMESTAMP + make_interval(secs => p_delivery_seconds),
    CURRENT_TIMESTAMP + make_interval(secs => p_delivery_seconds + p_auto_start_grace_seconds),
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
  );

  UPDATE public.task_attempts
  SET status = 'leased',
      routing_claim_owner = NULL,
      routing_claim_expires_at_utc = NULL
  WHERE id = p_task_attempt_id;

  UPDATE public.tasks
  SET lifecycle_status = 'assigned', updated_at_utc = CURRENT_TIMESTAMP
  WHERE id = v_task_id AND workspace_id = v_workspace_id;

  INSERT INTO public.outbox_events(
    id, workspace_id, event_type, aggregate_type, aggregate_id, aggregate_sequence,
    cloud_event_json, status, available_at_utc, attempt_count, created_at_utc
  ) VALUES (
    uuidv7(), v_workspace_id, 'assignment.leased', 'assignment', v_assignment_id::text, v_fence_token,
    jsonb_build_object(
      'specversion', '1.0',
      'id', uuidv7()::text,
      'source', 'urn:edgemint:router',
      'type', 'assignment.leased',
      'time', CURRENT_TIMESTAMP,
      'subject', v_assignment_id::text,
      'data', jsonb_build_object(
        'assignmentId', v_assignment_id,
        'workerDeviceId', p_worker_device_id,
        'taskAttemptId', p_task_attempt_id,
        'taskRunId', v_task_run_id,
        'fenceToken', v_fence_token,
        'leaseExpiresAt', v_expiry
      )
    ),
    'pending', CURRENT_TIMESTAMP, 0, CURRENT_TIMESTAMP
  );

  RETURN QUERY SELECT v_assignment_id, v_fence_token, v_expiry;
END
$$;

COMMENT ON FUNCTION public.acquire_assignment_lease IS
  'Lease assignment with TaskRun monotonic fence and reserve_task_run_budget(assignment).';

COMMIT;
