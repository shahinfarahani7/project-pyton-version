-- TaskRun aggregate budgets (v2 §9, §41–45, A14, T14).

ALTER TABLE public.task_runs
  ADD COLUMN IF NOT EXISTS max_attempts int NOT NULL DEFAULT 3
    CONSTRAINT CK_task_runs_max_attempts CHECK (max_attempts > 0),
  ADD COLUMN IF NOT EXISTS max_total_assignments int NOT NULL DEFAULT 6
    CONSTRAINT CK_task_runs_max_total_assignments CHECK (max_total_assignments > 0),
  ADD COLUMN IF NOT EXISTS max_cloud_fallbacks int NOT NULL DEFAULT 1
    CONSTRAINT CK_task_runs_max_cloud_fallbacks CHECK (max_cloud_fallbacks >= 0),
  ADD COLUMN IF NOT EXISTS attempt_count int NOT NULL DEFAULT 1
    CONSTRAINT CK_task_runs_attempt_count CHECK (attempt_count > 0),
  ADD COLUMN IF NOT EXISTS assignment_count int NOT NULL DEFAULT 0
    CONSTRAINT CK_task_runs_assignment_count CHECK (assignment_count >= 0),
  ADD COLUMN IF NOT EXISTS cloud_fallback_count int NOT NULL DEFAULT 0
    CONSTRAINT CK_task_runs_cloud_fallback_count CHECK (cloud_fallback_count >= 0);

CREATE OR REPLACE FUNCTION public.reserve_task_run_budget(
  p_task_run_id uuid,
  p_budget_kind text
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_row public.task_runs%ROWTYPE;
  v_updated int;
BEGIN
  SELECT *
  INTO v_row
  FROM public.task_runs
  WHERE id = p_task_run_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'task run not found';
  END IF;

  IF v_row.terminal_committed_at_utc IS NOT NULL THEN
    RETURN false;
  END IF;

  IF p_budget_kind = 'assignment' THEN
    IF v_row.assignment_count >= v_row.max_total_assignments THEN
      RETURN false;
    END IF;
    UPDATE public.task_runs
    SET assignment_count = assignment_count + 1,
        updated_at_utc = CURRENT_TIMESTAMP
    WHERE id = p_task_run_id;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN v_updated = 1;
  END IF;

  IF p_budget_kind = 'attempt' THEN
    IF v_row.attempt_count >= v_row.max_attempts THEN
      RETURN false;
    END IF;
    UPDATE public.task_runs
    SET attempt_count = attempt_count + 1,
        updated_at_utc = CURRENT_TIMESTAMP
    WHERE id = p_task_run_id;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN v_updated = 1;
  END IF;

  IF p_budget_kind = 'cloud_fallback' THEN
    IF v_row.cloud_fallback_count >= v_row.max_cloud_fallbacks THEN
      RETURN false;
    END IF;
    UPDATE public.task_runs
    SET cloud_fallback_count = cloud_fallback_count + 1,
        updated_at_utc = CURRENT_TIMESTAMP
    WHERE id = p_task_run_id;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN v_updated = 1;
  END IF;

  RAISE EXCEPTION 'unknown task run budget kind: %', p_budget_kind;
END;
$$;

COMMENT ON FUNCTION public.reserve_task_run_budget IS
  'Reserve TaskRun-wide assignment/attempt/cloud budget; counters never reset on new Attempt (v2 §1436).';
