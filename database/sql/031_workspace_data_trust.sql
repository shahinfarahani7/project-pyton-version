-- Workspace data-policy bindings and worker session revocation (v2 §52, §61, A07, T07).


BEGIN;
CREATE TABLE IF NOT EXISTS public.workspace_data_policy_bindings (
  workspace_id uuid NOT NULL PRIMARY KEY,
  data_policy_ref varchar(128) NOT NULL,
  default_execution_policy varchar(32) NOT NULL DEFAULT 'edge_preferred'
    CONSTRAINT CK_workspace_data_policy_execution
    CHECK (default_execution_policy IN ('edge_only', 'edge_preferred', 'cloud_permitted')),
  cloud_fallback_allowed boolean NOT NULL DEFAULT TRUE,
  data_region varchar(32) NOT NULL DEFAULT 'eu-central',
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_workspace_data_policy_workspace
    FOREIGN KEY (workspace_id) REFERENCES public.workspaces (id)
);

ALTER TABLE public.worker_sessions
  ADD COLUMN IF NOT EXISTS revoked_at_utc timestamptz NULL;

CREATE INDEX IF NOT EXISTS IX_worker_sessions_active
  ON public.worker_sessions (worker_device_id, expires_at_utc DESC)
  WHERE revoked_at_utc IS NULL;

CREATE OR REPLACE FUNCTION public.revoke_worker_session(p_session_id uuid)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated int;
BEGIN
  UPDATE public.worker_sessions
  SET revoked_at_utc = CURRENT_TIMESTAMP
  WHERE id = p_session_id
    AND revoked_at_utc IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END;
$$;

COMMENT ON TABLE public.workspace_data_policy_bindings IS
  'Tenant-scoped data processing and Cloud destination policy binding (v2 §61).';

COMMENT ON FUNCTION public.revoke_worker_session IS
  'Revoke worker bearer session; revoked credentials must fail closed on access.';

COMMIT;
