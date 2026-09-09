-- Immutable checkpoint manifests and authenticated ResumeGrants (v2 §28, §46, A12, T12).


BEGIN;
CREATE TABLE IF NOT EXISTS public.checkpoint_manifests (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  task_run_id uuid NOT NULL,
  task_revision_id uuid NOT NULL,
  task_attempt_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  input_digest char(64) NOT NULL,
  execution_plan_id varchar(128) NOT NULL,
  execution_plan_version varchar(64) NOT NULL,
  stage_id varchar(128) NOT NULL,
  chunk_id varchar(128) NOT NULL,
  chunk_index int NOT NULL,
  chunker_version varchar(64) NOT NULL,
  tokenizer_version varchar(64) NOT NULL,
  prompt_template_version varchar(64) NOT NULL,
  model_version_id varchar(128) NOT NULL,
  artifact_digest char(64) NOT NULL,
  runtime_version varchar(64) NOT NULL,
  backend varchar(64) NOT NULL,
  producer_attempt_id uuid NOT NULL,
  producer_assignment_id uuid NOT NULL,
  producer_fence_token bigint NOT NULL,
  producer_worker_device_id uuid NOT NULL,
  producer_worker_boot_id varchar(128) NULL,
  processed_ranges_json jsonb NOT NULL,
  completed_chunk_ids_json jsonb NOT NULL,
  result_artifact_hash char(64) NOT NULL,
  validation_version varchar(64) NOT NULL DEFAULT 'checkpoint-v1',
  validation_status varchar(32) NOT NULL DEFAULT 'accepted'
    CONSTRAINT CK_checkpoint_manifests_validation_status
    CHECK (validation_status IN ('accepted', 'rejected', 'pending')),
  checkpoint_schema_version varchar(32) NOT NULL DEFAULT '1.0.0',
  retention_policy_version varchar(32) NOT NULL DEFAULT 'default-v1',
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_checkpoint_manifests_task_run
    FOREIGN KEY (task_run_id) REFERENCES public.task_runs (id),
  CONSTRAINT FK_checkpoint_manifests_assignment_scope
    FOREIGN KEY (assignment_id, workspace_id) REFERENCES public.assignments (id, workspace_id),
  CONSTRAINT UQ_checkpoint_manifest_chunk UNIQUE (task_run_id, input_digest, chunk_id)
);

CREATE INDEX IF NOT EXISTS IX_checkpoint_manifests_task_run_input
  ON public.checkpoint_manifests (task_run_id, input_digest, chunk_index);

CREATE TABLE IF NOT EXISTS public.resume_grants (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  task_run_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  fence_token bigint NOT NULL,
  worker_device_id uuid NOT NULL,
  checkpoint_manifest_id uuid NOT NULL,
  input_digest char(64) NOT NULL,
  authorized_chunk_ids_json jsonb NOT NULL,
  authorized_stage_ids_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  model_version_id varchar(128) NOT NULL,
  runtime_version varchar(64) NOT NULL,
  prompt_template_version varchar(64) NOT NULL,
  execution_plan_version varchar(64) NOT NULL,
  producer_fence_token bigint NOT NULL,
  producer_assignment_id uuid NOT NULL,
  status varchar(32) NOT NULL DEFAULT 'active'
    CONSTRAINT CK_resume_grants_status CHECK (status IN ('active', 'consumed', 'revoked', 'expired')),
  expires_at_utc timestamptz NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_resume_grants_checkpoint
    FOREIGN KEY (checkpoint_manifest_id) REFERENCES public.checkpoint_manifests (id),
  CONSTRAINT FK_resume_grants_assignment_scope
    FOREIGN KEY (assignment_id, workspace_id) REFERENCES public.assignments (id, workspace_id),
  CONSTRAINT UQ_resume_grants_assignment_fence UNIQUE (assignment_id, fence_token)
);

CREATE INDEX IF NOT EXISTS IX_resume_grants_task_run_active
  ON public.resume_grants (task_run_id, status, expires_at_utc DESC)
  WHERE status = 'active';

CREATE OR REPLACE FUNCTION public.issue_resume_grant(
  p_workspace_id uuid,
  p_task_run_id uuid,
  p_assignment_id uuid,
  p_fence_token bigint,
  p_worker_device_id uuid,
  p_checkpoint_manifest_id uuid,
  p_input_digest char(64),
  p_authorized_chunk_ids jsonb,
  p_authorized_stage_ids jsonb,
  p_model_version_id text,
  p_runtime_version text,
  p_prompt_template_version text,
  p_execution_plan_version text,
  p_producer_fence_token bigint,
  p_producer_assignment_id uuid,
  p_expires_at_utc timestamptz
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_manifest record;
  v_grant_id uuid;
BEGIN
  SELECT *
  INTO v_manifest
  FROM public.checkpoint_manifests
  WHERE id = p_checkpoint_manifest_id
    AND workspace_id = p_workspace_id
    AND task_run_id = p_task_run_id
    AND input_digest = p_input_digest
    AND validation_status = 'accepted';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'checkpoint manifest not accepted or mismatched scope';
  END IF;

  IF v_manifest.model_version_id <> p_model_version_id
     OR v_manifest.runtime_version <> p_runtime_version
     OR v_manifest.prompt_template_version <> p_prompt_template_version
     OR v_manifest.execution_plan_version <> p_execution_plan_version THEN
    RAISE EXCEPTION 'checkpoint compatibility mismatch';
  END IF;

  INSERT INTO public.resume_grants (
    workspace_id, task_run_id, assignment_id, fence_token, worker_device_id,
    checkpoint_manifest_id, input_digest, authorized_chunk_ids_json,
    authorized_stage_ids_json, model_version_id, runtime_version,
    prompt_template_version, execution_plan_version, producer_fence_token,
    producer_assignment_id, expires_at_utc, status
  ) VALUES (
    p_workspace_id, p_task_run_id, p_assignment_id, p_fence_token, p_worker_device_id,
    p_checkpoint_manifest_id, p_input_digest, p_authorized_chunk_ids,
    p_authorized_stage_ids, p_model_version_id, p_runtime_version,
    p_prompt_template_version, p_execution_plan_version, p_producer_fence_token,
    p_producer_assignment_id, p_expires_at_utc, 'active'
  )
  ON CONFLICT ON CONSTRAINT UQ_resume_grants_assignment_fence DO UPDATE
    SET checkpoint_manifest_id = EXCLUDED.checkpoint_manifest_id,
        authorized_chunk_ids_json = EXCLUDED.authorized_chunk_ids_json,
        authorized_stage_ids_json = EXCLUDED.authorized_stage_ids_json,
        expires_at_utc = EXCLUDED.expires_at_utc,
        status = 'active'
  RETURNING id INTO v_grant_id;

  RETURN v_grant_id;
END;
$$;

COMMENT ON TABLE public.checkpoint_manifests IS
  'Immutable checkpoint provenance manifest (v2 §28). Producer fence is provenance only.';

COMMENT ON TABLE public.resume_grants IS
  'Authenticated ResumeGrant binding accepted checkpoint ranges to a fresh Assignment grant (v2 §46).';

COMMENT ON FUNCTION public.issue_resume_grant IS
  'Issue or refresh ResumeGrant after compatibility checks; producer fence never authorizes writes alone.';

COMMIT;
