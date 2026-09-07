-- Immutable per-input ExecutionAllocation distinct from static ResourceEnvelope (v2 §12.1, A05, T05).

CREATE TABLE IF NOT EXISTS public.task_execution_allocations (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  task_run_id uuid NOT NULL,
  task_revision_id uuid NOT NULL,
  input_digest char(64) NOT NULL,
  resource_envelope_name varchar(128) NOT NULL,
  resource_envelope_version varchar(32) NOT NULL,
  execution_plan_name varchar(128) NOT NULL,
  execution_plan_version varchar(32) NOT NULL,
  policy_version varchar(64) NOT NULL,
  estimator_version varchar(64) NOT NULL,
  calibration_snapshot_id uuid NULL,
  cpu_units int NOT NULL
    CONSTRAINT CK_task_execution_allocations_cpu CHECK (cpu_units >= 0),
  memory_bytes bigint NOT NULL
    CONSTRAINT CK_task_execution_allocations_memory CHECK (memory_bytes >= 0),
  storage_bytes bigint NOT NULL
    CONSTRAINT CK_task_execution_allocations_storage CHECK (storage_bytes >= 0),
  accelerator_units int NOT NULL DEFAULT 0
    CONSTRAINT CK_task_execution_allocations_accel CHECK (accelerator_units >= 0),
  model_session_units int NOT NULL DEFAULT 1
    CONSTRAINT CK_task_execution_allocations_model_sessions CHECK (model_session_units >= 0),
  exclusive_group varchar(64) NOT NULL DEFAULT '',
  estimated_duration_ms int NOT NULL
    CONSTRAINT CK_task_execution_allocations_duration CHECK (estimated_duration_ms > 0),
  predicted_stage_count int NOT NULL DEFAULT 1
    CONSTRAINT CK_task_execution_allocations_stage_count CHECK (predicted_stage_count > 0),
  stage_peaks_json jsonb NOT NULL
    CONSTRAINT CK_task_execution_allocations_stage_peaks CHECK (
      jsonb_typeof(stage_peaks_json) = 'array'
    ),
  compatibility_profile_ref varchar(128) NULL,
  max_output_tokens int NOT NULL DEFAULT 4096
    CONSTRAINT CK_task_execution_allocations_max_output CHECK (max_output_tokens > 0),
  max_inference_calls int NOT NULL DEFAULT 1
    CONSTRAINT CK_task_execution_allocations_max_calls CHECK (max_inference_calls > 0),
  deadline_ms int NOT NULL DEFAULT 600000
    CONSTRAINT CK_task_execution_allocations_deadline CHECK (deadline_ms > 0),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_task_execution_allocations_task_run
    FOREIGN KEY (task_run_id) REFERENCES public.task_runs (id),
  CONSTRAINT FK_task_execution_allocations_revision_scope
    FOREIGN KEY (task_revision_id, workspace_id)
    REFERENCES public.task_revisions (id, workspace_id),
  CONSTRAINT UQ_task_execution_allocations_task_run UNIQUE (task_run_id),
  CONSTRAINT UQ_task_execution_allocations_identity UNIQUE (
    task_run_id, input_digest, execution_plan_version
  )
);

CREATE INDEX IF NOT EXISTS IX_task_execution_allocations_revision
  ON public.task_execution_allocations (task_revision_id, created_at_utc DESC);

ALTER TABLE public.assignments
  ADD COLUMN IF NOT EXISTS execution_allocation_id uuid NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'FK_assignments_execution_allocation'
  ) THEN
    ALTER TABLE public.assignments
      ADD CONSTRAINT FK_assignments_execution_allocation
      FOREIGN KEY (execution_allocation_id)
      REFERENCES public.task_execution_allocations (id);
  END IF;
END $$;

COMMENT ON TABLE public.task_execution_allocations IS
  'Immutable per TaskRun/input/plan resource decision; distinct from static revision envelope (v2 §12.1).';
