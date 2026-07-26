BEGIN;

CREATE TABLE IF NOT EXISTS public.organizations (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  public_id varchar(32) NOT NULL UNIQUE,
  name varchar(200) NOT NULL,
  status varchar(32) NOT NULL CONSTRAINT CK_organizations_status CHECK (status IN ('active','suspended','closed')),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS public.workspaces (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  organization_id uuid NOT NULL,
  public_id varchar(32) NOT NULL UNIQUE,
  name varchar(200) NOT NULL,
  status varchar(32) NOT NULL CONSTRAINT CK_workspaces_status CHECK (status IN ('active','suspended','closed')),
  data_region varchar(32) NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_workspaces_org FOREIGN KEY (organization_id) REFERENCES public.organizations(id),
  CONSTRAINT UQ_workspaces_scope UNIQUE (id, organization_id)
);

CREATE TABLE IF NOT EXISTS public.principals (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  subject varchar(255) NOT NULL UNIQUE,
  principal_type varchar(32) NOT NULL CONSTRAINT CK_principals_type CHECK (principal_type IN ('user','service','worker')),
  display_name varchar(200) NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS public.workspace_members (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  principal_id uuid NOT NULL,
  role_code varchar(64) NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_workspace_members_workspace FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id),
  CONSTRAINT FK_workspace_members_principal FOREIGN KEY (principal_id) REFERENCES public.principals(id),
  CONSTRAINT UQ_workspace_member UNIQUE (workspace_id, principal_id)
);

CREATE TABLE IF NOT EXISTS public.workspace_invitations (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  email varchar(320) NOT NULL,
  role_code varchar(64) NOT NULL,
  token_hash bytea NOT NULL,
  expires_at_utc timestamptz NOT NULL,
  accepted_at_utc timestamptz NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_workspace_invitations_workspace FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id)
);

CREATE TABLE IF NOT EXISTS public.api_credentials (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  public_id varchar(32) NOT NULL UNIQUE,
  secret_hash bytea NOT NULL,
  permissions_json jsonb NOT NULL CONSTRAINT CK_api_credentials_permissions_json CHECK (jsonb_typeof(permissions_json::jsonb) IS NOT NULL),
  expires_at_utc timestamptz NULL,
  revoked_at_utc timestamptz NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_api_credentials_workspace FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id)
);

COMMIT;
