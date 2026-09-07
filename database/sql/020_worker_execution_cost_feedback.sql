BEGIN;

CREATE TABLE IF NOT EXISTS public.worker_execution_cost_feedback (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  task_attempt_id uuid NOT NULL,
  worker_device_id uuid NOT NULL,
  fence_token bigint NOT NULL,
  task_type varchar(128) NOT NULL,
  observed_at_utc timestamptz NOT NULL,
  predicted_json jsonb NOT NULL,
  observed_json jsonb NOT NULL,
  variance_json jsonb NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_worker_execution_cost_feedback_assignment_scope
    FOREIGN KEY (assignment_id, workspace_id) REFERENCES public.assignments(id, workspace_id),
  CONSTRAINT FK_worker_execution_cost_feedback_attempt_scope
    FOREIGN KEY (task_attempt_id, workspace_id) REFERENCES public.task_attempts(id, workspace_id),
  CONSTRAINT FK_worker_execution_cost_feedback_device
    FOREIGN KEY (worker_device_id) REFERENCES public.worker_devices(id),
  CONSTRAINT CK_worker_execution_cost_feedback_predicted_json
    CHECK (jsonb_typeof(predicted_json) = 'object'),
  CONSTRAINT CK_worker_execution_cost_feedback_observed_json
    CHECK (jsonb_typeof(observed_json) = 'object'),
  CONSTRAINT CK_worker_execution_cost_feedback_variance_json
    CHECK (jsonb_typeof(variance_json) = 'object')
);

CREATE UNIQUE INDEX IF NOT EXISTS UQ_worker_execution_cost_feedback_assignment_fence
  ON public.worker_execution_cost_feedback (assignment_id, fence_token);

CREATE INDEX IF NOT EXISTS IX_worker_execution_cost_feedback_device_observed
  ON public.worker_execution_cost_feedback (worker_device_id, observed_at_utc DESC);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.worker_execution_cost_feedback TO edgemint_runtime;

COMMIT;
