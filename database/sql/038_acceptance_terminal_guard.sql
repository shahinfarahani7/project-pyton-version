-- Guard entitlement/candidate acceptance when terminal CAS loses the race.

BEGIN;

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

  IF NOT v_committed THEN
    terminal_committed := FALSE;
    entitlement_id := NULL;
    entitlement_is_new := FALSE;
    idempotency_receipt := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

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

COMMIT;
