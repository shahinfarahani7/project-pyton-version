-- One Idempotency-Key per operation scope inside a workspace.
-- api_credentials already stores the secret hash; name, prefix, scopes and
-- CIDR allow-lists live in permissions_json for keys issued by the directory.

BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS ux_idempotency_scope_key
  ON public.idempotency_records (workspace_id, scope, idempotency_key);

COMMIT;
