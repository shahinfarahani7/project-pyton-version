-- Idempotent development seed for local Docker and manual testing.
-- Fixed UUIDs align with customer-portal dev login (session.js).

BEGIN;

INSERT INTO public.organizations (id, public_id, name, status)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'org_dev_primary',
  'EdgeMint Demo Org',
  'active'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.workspaces (id, organization_id, public_id, name, status, data_region)
VALUES
  (
    '00000000-0000-0000-0000-00000000000b',
    '00000000-0000-0000-0000-000000000001',
    'ws_dev_primary',
    'Primary workspace',
    'active',
    'eu-west-1'
  ),
  (
    '00000000-0000-0000-0000-00000000000c',
    '00000000-0000-0000-0000-000000000001',
    'ws_dev_staging',
    'Staging workspace',
    'active',
    'eu-central-1'
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.principals (id, subject, principal_type, display_name)
VALUES (
  '00000000-0000-0000-0000-00000000000a',
  'dev-user@edgemint.local',
  'user',
  'Dev User'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.workspace_members (id, workspace_id, principal_id, role_code)
VALUES
  (
    '00000000-0000-0000-0000-000000000011',
    '00000000-0000-0000-0000-00000000000b',
    '00000000-0000-0000-0000-00000000000a',
    'workspace_admin'
  ),
  (
    '00000000-0000-0000-0000-000000000012',
    '00000000-0000-0000-0000-00000000000c',
    '00000000-0000-0000-0000-00000000000a',
    'workspace_admin'
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tasks (
  id, workspace_id, public_id, task_type, lifecycle_status, idempotency_key, priority_class
)
VALUES
  (
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-00000000000b',
    'tsk_dev_ocr_running',
    'document.ocr',
    'running',
    'seed-primary-ocr-running',
    'standard'
  ),
  (
    '00000000-0000-0000-0000-000000000102',
    '00000000-0000-0000-0000-00000000000b',
    'tsk_dev_nlp_done',
    'text.summarize',
    'succeeded',
    'seed-primary-nlp-done',
    'batch'
  ),
  (
    '00000000-0000-0000-0000-000000000103',
    '00000000-0000-0000-0000-00000000000b',
    'tsk_dev_vision_queued',
    'image.classify',
    'queued',
    'seed-primary-vision-queued',
    'high'
  ),
  (
    '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-00000000000c',
    'tsk_dev_staging_draft',
    'document.ocr',
    'draft',
    'seed-staging-draft',
    'standard'
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.api_credentials (
  id, workspace_id, public_id, secret_hash, permissions_json, expires_at_utc
)
VALUES
  (
    '00000000-0000-0000-0000-000000000301',
    '00000000-0000-0000-0000-00000000000b',
    'key_dev_primary_live',
    decode('deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef', 'hex'),
    '["customer.tasks:read","customer.tasks:write"]'::jsonb,
    NULL
  ),
  (
    '00000000-0000-0000-0000-000000000302',
    '00000000-0000-0000-0000-00000000000b',
    'key_dev_primary_ro',
    decode('cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe', 'hex'),
    '["customer.tasks:read"]'::jsonb,
    NULL
  ),
  (
    '00000000-0000-0000-0000-000000000303',
    '00000000-0000-0000-0000-00000000000c',
    'key_dev_staging',
    decode('feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface', 'hex'),
    '["customer.tasks:read","customer.tasks:write"]'::jsonb,
    NULL
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.webhook_endpoints (
  id, workspace_id, url, secret_hash, event_types_json, status
)
VALUES
  (
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-00000000000b',
    'https://hooks.example.dev/edgemint/primary',
    decode('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef', 'hex'),
    '["task.succeeded","task.failed"]'::jsonb,
    'active'
  ),
  (
    '00000000-0000-0000-0000-000000000402',
    '00000000-0000-0000-0000-00000000000b',
    'https://hooks.example.dev/edgemint/billing',
    decode('abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789', 'hex'),
    '["invoice.finalized"]'::jsonb,
    'paused'
  ),
  (
    '00000000-0000-0000-0000-000000000403',
    '00000000-0000-0000-0000-00000000000c',
    'https://staging.example.dev/edgemint/events',
    decode('9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba', 'hex'),
    '["task.succeeded"]'::jsonb,
    'active'
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.invoices (
  id, workspace_id, organization_id, amount_due_micro_eur, status, provider_invoice_id
)
VALUES
  (
    '00000000-0000-0000-0000-000000000501',
    '00000000-0000-0000-0000-00000000000b',
    '00000000-0000-0000-0000-000000000001',
    125000000,
    'open',
    'inv_dev_open_001'
  ),
  (
    '00000000-0000-0000-0000-000000000502',
    '00000000-0000-0000-0000-00000000000b',
    '00000000-0000-0000-0000-000000000001',
    89000000,
    'paid',
    'inv_dev_paid_002'
  ),
  (
    '00000000-0000-0000-0000-000000000503',
    '00000000-0000-0000-0000-00000000000c',
    '00000000-0000-0000-0000-000000000001',
    42000000,
    'draft',
    NULL
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.disputes (id, workspace_id, task_id, status, reason_code)
VALUES
  (
    '00000000-0000-0000-0000-000000000601',
    '00000000-0000-0000-0000-00000000000b',
    '00000000-0000-0000-0000-000000000102',
    'open',
    'quality'
  ),
  (
    '00000000-0000-0000-0000-000000000602',
    '00000000-0000-0000-0000-00000000000b',
    NULL,
    'resolved',
    'billing'
  ),
  (
    '00000000-0000-0000-0000-000000000603',
    '00000000-0000-0000-0000-00000000000c',
    NULL,
    'open',
    'sla'
  )
ON CONFLICT (id) DO NOTHING;

COMMIT;
