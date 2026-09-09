-- Runtime upgrade evaluation records (v2 §32.1, A24 / T24).


BEGIN;
CREATE TABLE IF NOT EXISTS public.runtime_upgrade_evaluations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_runtime_class text NOT NULL,
  candidate_model_version_id text,
  current_runtime_class text NOT NULL,
  current_model_version_id text,
  evaluation_status text NOT NULL
    CONSTRAINT CK_runtime_upgrade_evaluation_status
    CHECK (evaluation_status IN ('approved', 'rejected', 'rollback_required')),
  rollback_version_id uuid,
  benchmark_evidence_path text,
  compatibility_profile_id text,
  dimension_results_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  rejection_reason text,
  evaluated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  evaluated_by text NOT NULL DEFAULT 'system'
);

CREATE INDEX IF NOT EXISTS IX_runtime_upgrade_evaluations_status
  ON public.runtime_upgrade_evaluations (evaluation_status, evaluated_at_utc DESC);

COMMIT;
