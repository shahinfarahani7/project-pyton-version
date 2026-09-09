-- TaskRun identity and terminal transition CAS (Architecture v2 §20, A01, T01).

BEGIN;

CREATE TABLE IF NOT EXISTS public.task_runs (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  task_id uuid NOT NULL,
  task_revision_id uuid NOT NULL,
  client_request_key varchar(128) NULL,
  input_digest char(64) NOT NULL,
  status varchar(32) NOT NULL DEFAULT 'pending',
  terminal_outcome varchar(64) NULL,
  terminal_committed_at_utc timestamptz NULL,
  generation int NOT NULL DEFAULT 1 CONSTRAINT CK_task_runs_generation CHECK (generation > 0),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_task_runs_task_scope
    FOREIGN KEY (task_id, workspace_id) REFERENCES public.tasks (id, workspace_id),
  CONSTRAINT FK_task_runs_revision_scope
    FOREIGN KEY (task_revision_id, workspace_id) REFERENCES public.task_revisions (id, workspace_id),
  CONSTRAINT CK_task_runs_status CHECK (
    status IN (
      'pending', 'routing', 'queued', 'executing', 'validating',
      'succeeded', 'partial_succeeded', 'failed', 'cancelled', 'deadline_expired'
    )
  ),
  CONSTRAINT UQ_task_runs_client_dedup UNIQUE (workspace_id, client_request_key, input_digest)
);

CREATE INDEX IF NOT EXISTS ix_task_runs_workspace_status
  ON public.task_runs (workspace_id, status, created_at_utc DESC);

ALTER TABLE public.task_attempts
  ADD COLUMN IF NOT EXISTS task_run_id uuid NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'FK_task_attempts_task_run'
  ) THEN
    ALTER TABLE public.task_attempts
      ADD CONSTRAINT FK_task_attempts_task_run
      FOREIGN KEY (task_run_id) REFERENCES public.task_runs (id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.commit_task_run_terminal(
  p_task_run_id uuid,
  p_terminal_status text,
  p_terminal_outcome text
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated int;
BEGIN
  IF p_terminal_status NOT IN (
    'succeeded', 'partial_succeeded', 'failed', 'cancelled', 'deadline_expired'
  ) THEN
    RAISE EXCEPTION 'invalid terminal status: %', p_terminal_status;
  END IF;

  UPDATE public.task_runs
  SET status = p_terminal_status,
      terminal_outcome = p_terminal_outcome,
      terminal_committed_at_utc = CURRENT_TIMESTAMP,
      updated_at_utc = CURRENT_TIMESTAMP
  WHERE id = p_task_run_id
    AND terminal_committed_at_utc IS NULL
    AND status IN ('pending', 'routing', 'queued', 'executing', 'validating');

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END;
$$;

COMMENT ON TABLE public.task_runs IS
  'Logical customer request (TaskRun) distinct from immutable TaskRevision (v2 §20, §60).';

COMMENT ON FUNCTION public.commit_task_run_terminal IS
  'Atomic terminal transition: first valid commit wins; later commits return false.';

COMMIT;
