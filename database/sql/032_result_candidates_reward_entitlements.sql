-- ResultCandidate, RewardEntitlement, and external-effect deduplication (v2 §22–23, §50–51, A08, T08).


BEGIN;
CREATE TABLE IF NOT EXISTS public.result_candidates (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  task_run_id uuid NOT NULL,
  task_attempt_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  generation int NOT NULL CONSTRAINT CK_result_candidates_generation CHECK (generation > 0),
  result_sha256 char(64) NOT NULL,
  worker_device_id uuid NOT NULL,
  fence_token int NOT NULL,
  status varchar(32) NOT NULL DEFAULT 'pinned'
    CONSTRAINT CK_result_candidates_status
    CHECK (status IN ('pinned', 'superseded', 'accepted', 'rejected')),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_result_candidates_task_run
    FOREIGN KEY (task_run_id) REFERENCES public.task_runs (id),
  CONSTRAINT FK_result_candidates_attempt_scope
    FOREIGN KEY (task_attempt_id, workspace_id) REFERENCES public.task_attempts (id, workspace_id),
  CONSTRAINT FK_result_candidates_assignment_scope
    FOREIGN KEY (assignment_id, workspace_id) REFERENCES public.assignments (id, workspace_id),
  CONSTRAINT UQ_result_candidates_run_digest UNIQUE (task_run_id, result_sha256),
  CONSTRAINT UQ_result_candidates_assignment UNIQUE (assignment_id, result_sha256)
);

CREATE INDEX IF NOT EXISTS IX_result_candidates_workspace_run
  ON public.result_candidates (workspace_id, task_run_id, created_at_utc DESC);

CREATE TABLE IF NOT EXISTS public.result_validation_records (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  result_candidate_id uuid NOT NULL,
  validation_status varchar(32) NOT NULL
    CONSTRAINT CK_result_validation_status
    CHECK (validation_status IN ('passed', 'failed', 'error')),
  validator_version varchar(64) NOT NULL,
  failure_code varchar(64) NULL,
  detail text NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_result_validation_candidate
    FOREIGN KEY (result_candidate_id) REFERENCES public.result_candidates (id),
  CONSTRAINT UQ_result_validation_candidate UNIQUE (result_candidate_id)
);

CREATE TABLE IF NOT EXISTS public.reward_entitlements (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  task_run_id uuid NOT NULL,
  entitlement_component_id varchar(64) NOT NULL DEFAULT 'completion',
  result_candidate_id uuid NOT NULL,
  worker_device_id uuid NOT NULL,
  amount_micro_eur bigint NOT NULL DEFAULT 0
    CONSTRAINT CK_reward_entitlements_amount CHECK (amount_micro_eur >= 0),
  status varchar(32) NOT NULL DEFAULT 'recorded'
    CONSTRAINT CK_reward_entitlements_status
    CHECK (status IN ('pending', 'recorded', 'ineligible')),
  idempotency_receipt varchar(128) NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_reward_entitlements_task_run
    FOREIGN KEY (task_run_id) REFERENCES public.task_runs (id),
  CONSTRAINT FK_reward_entitlements_candidate
    FOREIGN KEY (result_candidate_id) REFERENCES public.result_candidates (id),
  CONSTRAINT UQ_reward_entitlement_business_key
    UNIQUE (workspace_id, task_run_id, entitlement_component_id),
  CONSTRAINT UQ_reward_entitlement_receipt UNIQUE (idempotency_receipt)
);

CREATE TABLE IF NOT EXISTS public.external_effect_receipts (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  destination_type varchar(64) NOT NULL,
  destination_id varchar(255) NOT NULL,
  idempotency_key varchar(255) NOT NULL,
  payload_digest char(64) NOT NULL,
  effect_status varchar(32) NOT NULL DEFAULT 'issued'
    CONSTRAINT CK_external_effect_status
    CHECK (effect_status IN ('issued', 'reconciled', 'failed')),
  response_json jsonb NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT UQ_external_effect_dedup
    UNIQUE (destination_type, destination_id, idempotency_key)
);

ALTER TABLE public.results
  ADD COLUMN IF NOT EXISTS result_candidate_id uuid NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'FK_results_result_candidate'
  ) THEN
    ALTER TABLE public.results
      ADD CONSTRAINT FK_results_result_candidate
      FOREIGN KEY (result_candidate_id) REFERENCES public.result_candidates (id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.pin_result_candidate(
  p_workspace_id uuid,
  p_task_run_id uuid,
  p_task_attempt_id uuid,
  p_assignment_id uuid,
  p_generation int,
  p_result_sha256 char(64),
  p_worker_device_id uuid,
  p_fence_token int
) RETURNS TABLE (
  candidate_id uuid,
  is_new boolean
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.result_candidates (
    workspace_id, task_run_id, task_attempt_id, assignment_id,
    generation, result_sha256, worker_device_id, fence_token, status
  ) VALUES (
    p_workspace_id, p_task_run_id, p_task_attempt_id, p_assignment_id,
    p_generation, p_result_sha256, p_worker_device_id, p_fence_token, 'pinned'
  )
  ON CONFLICT ON CONSTRAINT UQ_result_candidates_assignment DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NOT NULL THEN
    candidate_id := v_id;
    is_new := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT rc.id INTO v_id
  FROM public.result_candidates AS rc
  WHERE rc.assignment_id = p_assignment_id
    AND rc.result_sha256 = p_result_sha256;

  candidate_id := v_id;
  is_new := FALSE;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_result_validation(
  p_workspace_id uuid,
  p_result_candidate_id uuid,
  p_validation_status text,
  p_validator_version text,
  p_failure_code text DEFAULT NULL,
  p_detail text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_validation_status NOT IN ('passed', 'failed', 'error') THEN
    RAISE EXCEPTION 'invalid validation status: %', p_validation_status;
  END IF;

  INSERT INTO public.result_validation_records (
    workspace_id, result_candidate_id, validation_status,
    validator_version, failure_code, detail
  ) VALUES (
    p_workspace_id, p_result_candidate_id, p_validation_status,
    p_validator_version, p_failure_code, p_detail
  )
  ON CONFLICT ON CONSTRAINT UQ_result_validation_candidate DO UPDATE
    SET validation_status = EXCLUDED.validation_status,
        validator_version = EXCLUDED.validator_version,
        failure_code = EXCLUDED.failure_code,
        detail = EXCLUDED.detail
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_task_run_with_entitlement(
  p_workspace_id uuid,
  p_task_run_id uuid,
  p_result_candidate_id uuid,
  p_worker_device_id uuid,
  p_amount_micro_eur bigint,
  p_terminal_status text,
  p_terminal_outcome text,
  p_entitlement_component_id text DEFAULT 'completion'
) RETURNS TABLE (
  terminal_committed boolean,
  entitlement_id uuid,
  entitlement_is_new boolean,
  idempotency_receipt text
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_validation_passed boolean;
  v_committed boolean;
  v_entitlement_id uuid;
  v_receipt text;
  v_is_new boolean := FALSE;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.result_validation_records AS rv
    WHERE rv.result_candidate_id = p_result_candidate_id
      AND rv.validation_status = 'passed'
  ) INTO v_validation_passed;

  IF NOT v_validation_passed THEN
    RAISE EXCEPTION 'candidate validation not passed: %', p_result_candidate_id;
  END IF;

  v_committed := public.commit_task_run_terminal(
    p_task_run_id, p_terminal_status, p_terminal_outcome
  );

  v_receipt := format(
    'ent:%s:%s:%s',
    p_workspace_id::text,
    p_task_run_id::text,
    p_entitlement_component_id
  );

  INSERT INTO public.reward_entitlements (
    workspace_id, task_run_id, entitlement_component_id,
    result_candidate_id, worker_device_id, amount_micro_eur,
    status, idempotency_receipt
  ) VALUES (
    p_workspace_id, p_task_run_id, p_entitlement_component_id,
    p_result_candidate_id, p_worker_device_id, p_amount_micro_eur,
    CASE WHEN p_amount_micro_eur > 0 THEN 'recorded' ELSE 'ineligible' END,
    v_receipt
  )
  ON CONFLICT ON CONSTRAINT UQ_reward_entitlement_business_key DO NOTHING
  RETURNING id INTO v_entitlement_id;

  IF v_entitlement_id IS NOT NULL THEN
    v_is_new := TRUE;
  ELSE
    SELECT re.id INTO v_entitlement_id
    FROM public.reward_entitlements AS re
    WHERE re.workspace_id = p_workspace_id
      AND re.task_run_id = p_task_run_id
      AND re.entitlement_component_id = p_entitlement_component_id;
  END IF;

  UPDATE public.result_candidates
  SET status = 'accepted'
  WHERE id = p_result_candidate_id
    AND status = 'pinned';

  terminal_committed := v_committed;
  entitlement_id := v_entitlement_id;
  entitlement_is_new := v_is_new;
  idempotency_receipt := v_receipt;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_external_effect_receipt(
  p_destination_type text,
  p_destination_id text,
  p_idempotency_key text,
  p_payload_digest char(64),
  p_response_json jsonb DEFAULT NULL
) RETURNS TABLE (
  receipt_id uuid,
  is_new boolean,
  conflict boolean
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
  v_existing_digest char(64);
BEGIN
  INSERT INTO public.external_effect_receipts (
    destination_type, destination_id, idempotency_key,
    payload_digest, response_json, effect_status
  ) VALUES (
    p_destination_type, p_destination_id, p_idempotency_key,
    p_payload_digest, p_response_json, 'issued'
  )
  ON CONFLICT ON CONSTRAINT UQ_external_effect_dedup DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NOT NULL THEN
    receipt_id := v_id;
    is_new := TRUE;
    conflict := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT eer.id, eer.payload_digest
  INTO v_id, v_existing_digest
  FROM public.external_effect_receipts AS eer
  WHERE eer.destination_type = p_destination_type
    AND eer.destination_id = p_destination_id
    AND eer.idempotency_key = p_idempotency_key;

  receipt_id := v_id;
  is_new := FALSE;
  conflict := (v_existing_digest IS DISTINCT FROM p_payload_digest);
  RETURN NEXT;
END;
$$;

COMMENT ON TABLE public.result_candidates IS
  'Immutable uploaded result candidate pinned to TaskRun generation (v2 §23).';

COMMENT ON TABLE public.reward_entitlements IS
  'Idempotent reward entitlement keyed by (workspace, taskRun, component) (v2 §51.1).';

COMMENT ON TABLE public.external_effect_receipts IS
  'Destination idempotency receipts for payout/webhook external effects (v2 §50.6).';

COMMENT ON FUNCTION public.accept_task_run_with_entitlement IS
  'CAS terminal TaskRun outcome and record reward entitlement atomically after validation passed.';

COMMIT;
