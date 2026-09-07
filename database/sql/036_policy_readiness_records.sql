-- Policy readiness records for v2 §73 activation gate (A23 / T23).

CREATE TABLE IF NOT EXISTS public.policy_readiness_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  architecture_version text NOT NULL,
  policy_version_hash char(64) NOT NULL,
  runtime_profile_scope text NOT NULL,
  responsible_owner text NOT NULL,
  values_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  evidence_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  compatibility_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  feature_flags_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  activation_status text NOT NULL DEFAULT 'closed'
    CONSTRAINT CK_policy_readiness_activation_status
    CHECK (activation_status IN ('closed', 'open')),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT UQ_policy_readiness_version_hash UNIQUE (policy_version_hash)
);

CREATE INDEX IF NOT EXISTS IX_policy_readiness_architecture_version
  ON public.policy_readiness_records (architecture_version, activation_status);
