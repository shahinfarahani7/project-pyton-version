BEGIN;

CREATE TABLE IF NOT EXISTS public.files (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  public_id varchar(32) NOT NULL UNIQUE,
  object_key varchar(1024) NOT NULL,
  content_type varchar(255) NOT NULL,
  size_bytes bigint NOT NULL CONSTRAINT CK_files_size CHECK (size_bytes>=0),
  sha256 char(64) NOT NULL,
  status varchar(32) NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_files_workspace FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id),
  CONSTRAINT UQ_files_workspace UNIQUE (id,workspace_id)
);

CREATE TABLE IF NOT EXISTS public.file_upload_sessions (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  file_id uuid NOT NULL,
  status varchar(32) NOT NULL,
  expires_at_utc timestamptz NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_file_upload_sessions_file_scope FOREIGN KEY (file_id,workspace_id) REFERENCES public.files(id,workspace_id)
);

CREATE TABLE IF NOT EXISTS public.models (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  public_id varchar(32) NOT NULL UNIQUE,
  name varchar(200) NOT NULL,
  task_type varchar(64) NOT NULL,
  status varchar(32) NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS public.model_versions (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  model_id uuid NOT NULL,
  semantic_version varchar(64) NOT NULL,
  artifact_uri varchar(1024) NOT NULL,
  artifact_sha256 char(64) NOT NULL,
  signature_uri varchar(1024) NOT NULL,
  license_spdx varchar(128) NOT NULL,
  status varchar(32) NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_model_versions_model FOREIGN KEY (model_id) REFERENCES public.models(id),
  CONSTRAINT UQ_model_version UNIQUE(model_id,semantic_version)
);

CREATE TABLE IF NOT EXISTS public.tasks (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  public_id varchar(32) NOT NULL UNIQUE,
  task_type varchar(64) NOT NULL,
  lifecycle_status varchar(32) NOT NULL CONSTRAINT CK_tasks_status CHECK (lifecycle_status IN ('draft','submitted','admitted','queued','assigned','running','verifying','succeeded','failed','cancelled','expired')),
  current_revision_id uuid NULL,
  idempotency_key varchar(200) NOT NULL,
  priority_class varchar(16) NOT NULL DEFAULT 'standard' CONSTRAINT CK_tasks_priority_class CHECK(priority_class IN('critical','high','standard','batch')),
  priority_bps int NOT NULL DEFAULT 2000 CONSTRAINT CK_tasks_priority_bps CHECK(priority_bps IN(1000,2000,3000,4000)),
  submitted_at_utc timestamptz NULL,
  deadline_at_utc timestamptz NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_tasks_workspace FOREIGN KEY(workspace_id) REFERENCES public.workspaces(id),
  CONSTRAINT UQ_tasks_scope UNIQUE(id,workspace_id),
  CONSTRAINT UQ_tasks_idempotency UNIQUE(workspace_id,idempotency_key)
);

CREATE TABLE IF NOT EXISTS public.task_revisions (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  task_id uuid NOT NULL,
  revision_number int NOT NULL CONSTRAINT CK_task_revisions_number CHECK(revision_number>0),
  model_version_id uuid NULL,
  input_file_id uuid NULL,
  inline_text text NULL,
  parameters_json jsonb NOT NULL CONSTRAINT CK_task_revisions_json CHECK(jsonb_typeof(parameters_json::jsonb) IS NOT NULL),
  required_device_tier varchar(8) NOT NULL DEFAULT 'T1' CONSTRAINT CK_task_revisions_required_tier CHECK(required_device_tier IN('T1','T2','T3','T4')),
  required_runtime_abi varchar(64) NOT NULL DEFAULT 'any',
  minimum_free_ram_bytes bigint NOT NULL DEFAULT 0 CONSTRAINT CK_task_revisions_min_ram CHECK(minimum_free_ram_bytes>=0),
  minimum_free_storage_bytes bigint NOT NULL DEFAULT 0 CONSTRAINT CK_task_revisions_min_storage CHECK(minimum_free_storage_bytes>=0),
  allowed_worker_regions_json jsonb NOT NULL DEFAULT '["*"]' CONSTRAINT CK_task_revisions_allowed_regions CHECK(jsonb_typeof(allowed_worker_regions_json::jsonb) IS NOT NULL),
  submitted_at_utc timestamptz NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_task_revisions_task_scope FOREIGN KEY(task_id,workspace_id) REFERENCES public.tasks(id,workspace_id),
  CONSTRAINT FK_task_revisions_model FOREIGN KEY(model_version_id) REFERENCES public.model_versions(id),
  CONSTRAINT FK_task_revisions_file_scope FOREIGN KEY(input_file_id,workspace_id) REFERENCES public.files(id,workspace_id),
  CONSTRAINT CK_task_revision_input CHECK((input_file_id IS NOT NULL AND inline_text IS NULL) OR (input_file_id IS NULL AND inline_text IS NOT NULL)),
  CONSTRAINT UQ_task_revision UNIQUE(task_id,revision_number),
  CONSTRAINT UQ_task_revision_scope UNIQUE(id,workspace_id)
);

CREATE TABLE IF NOT EXISTS public.task_attempts (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  task_id uuid NOT NULL,
  attempt_number int NOT NULL,
  status varchar(32) NOT NULL,
  estimated_execution_milliseconds int NOT NULL DEFAULT 1000 CONSTRAINT CK_task_attempts_estimated_ms CHECK(estimated_execution_milliseconds>0),
  routing_claim_owner varchar(128) NULL,
  routing_claim_expires_at_utc timestamptz NULL,
  started_at_utc timestamptz NULL,
  completed_at_utc timestamptz NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_task_attempts_task_scope FOREIGN KEY(task_id,workspace_id) REFERENCES public.tasks(id,workspace_id),
  CONSTRAINT UQ_task_attempt UNIQUE(task_id,attempt_number),
  CONSTRAINT UQ_task_attempt_scope UNIQUE(id,workspace_id)
);

CREATE TABLE IF NOT EXISTS public.workspace_routing_fairness (
  workspace_id uuid NOT NULL PRIMARY KEY,
  deficit_units int NOT NULL DEFAULT 0 CONSTRAINT CK_workspace_routing_deficit CHECK(deficit_units BETWEEN -100000 AND 100000),
  consecutive_assignments int NOT NULL DEFAULT 0 CONSTRAINT CK_workspace_routing_consecutive CHECK(consecutive_assignments>=0),
  last_selected_at_utc timestamptz NULL,
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  row_version bigint DEFAULT 0 NOT NULL,
  CONSTRAINT FK_workspace_routing_fairness_workspace FOREIGN KEY(workspace_id) REFERENCES public.workspaces(id)
);

CREATE TABLE IF NOT EXISTS public.task_state_history (
  id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL PRIMARY KEY,
  workspace_id uuid NOT NULL,
  task_id uuid NOT NULL,
  from_status varchar(32) NULL,
  to_status varchar(32) NOT NULL,
  reason_code varchar(64) NULL,
  changed_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_task_state_history_task_scope FOREIGN KEY(task_id,workspace_id) REFERENCES public.tasks(id,workspace_id)
);

CREATE TABLE IF NOT EXISTS public.workers (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  principal_id uuid NOT NULL,
  public_id varchar(32) NOT NULL UNIQUE,
  status varchar(32) NOT NULL,
  trust_bps int NOT NULL DEFAULT 6500 CONSTRAINT CK_workers_trust CHECK(trust_bps BETWEEN 0 AND 10000),
  reliability_bps int NOT NULL CONSTRAINT CK_workers_reliability CHECK(reliability_bps BETWEEN 0 AND 10000),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_workers_principal FOREIGN KEY(principal_id) REFERENCES public.principals(id)
);

CREATE TABLE IF NOT EXISTS public.worker_devices (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_id uuid NOT NULL,
  public_id varchar(32) NOT NULL UNIQUE,
  platform varchar(32) NOT NULL,
  app_version varchar(32) NOT NULL,
  runtime_abi varchar(64) NOT NULL,
  region_code varchar(64) NOT NULL DEFAULT 'unknown',
  device_tier varchar(8) NOT NULL,
  attestation_status varchar(32) NOT NULL,
  attestation_expires_at_utc timestamptz NOT NULL,
  status varchar(32) NOT NULL,
  last_seen_at_utc timestamptz NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_worker_devices_worker FOREIGN KEY(worker_id) REFERENCES public.workers(id)
);

CREATE TABLE IF NOT EXISTS public.worker_sessions (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_device_id uuid NOT NULL,
  session_token_hash bytea NOT NULL,
  expires_at_utc timestamptz NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_worker_sessions_device FOREIGN KEY(worker_device_id) REFERENCES public.worker_devices(id)
);

CREATE TABLE IF NOT EXISTS public.worker_consents (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_id uuid NOT NULL,
  policy_version varchar(64) NOT NULL,
  accepted_at_utc timestamptz NOT NULL,
  withdrawn_at_utc timestamptz NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_worker_consents_worker FOREIGN KEY(worker_id) REFERENCES public.workers(id)
);

CREATE TABLE IF NOT EXISTS public.worker_preferences (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_id uuid NOT NULL,
  version bigint NOT NULL DEFAULT 1 CONSTRAINT CK_worker_preferences_version CHECK(version>0),
  availability varchar(16) NOT NULL DEFAULT 'unavailable' CONSTRAINT CK_worker_preferences_availability CHECK(availability IN('available','unavailable')),
  network_policy varchar(32) NOT NULL DEFAULT 'wifi_only' CONSTRAINT CK_worker_preferences_network CHECK(network_policy IN('wifi_only','unmetered_only','wifi_or_ethernet','any_online')),
  charging_policy varchar(24) NOT NULL DEFAULT 'preferred' CONSTRAINT CK_worker_preferences_charging CHECK(charging_policy IN('required','preferred','not_required')),
  minimum_battery_percent smallint NOT NULL DEFAULT 25 CONSTRAINT CK_worker_preferences_battery CHECK(minimum_battery_percent BETWEEN 25 AND 100),
  schedule_json jsonb NOT NULL CONSTRAINT CK_worker_preferences_schedule_json CHECK(jsonb_typeof(schedule_json::jsonb) IS NOT NULL),
  schedule_mode varchar(24) NOT NULL DEFAULT 'always' CONSTRAINT CK_worker_preferences_schedule_mode CHECK(schedule_mode IN('always','charging_window','custom')),
  effective_window_start_utc timestamptz NULL,
  effective_window_end_utc timestamptz NULL,
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_worker_preferences_worker FOREIGN KEY(worker_id) REFERENCES public.workers(id),
  CONSTRAINT UQ_worker_preferences_worker UNIQUE(worker_id),
  CONSTRAINT CK_worker_preferences_effective_window CHECK((schedule_mode='always' AND effective_window_start_utc IS NULL AND effective_window_end_utc IS NULL) OR (schedule_mode<>'always' AND effective_window_start_utc IS NOT NULL AND effective_window_end_utc>effective_window_start_utc))
);

CREATE TABLE IF NOT EXISTS public.worker_benchmarks (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_device_id uuid NOT NULL,
  benchmark_json jsonb NOT NULL CONSTRAINT CK_worker_benchmarks_json CHECK(jsonb_typeof(benchmark_json::jsonb) IS NOT NULL),
  measured_at_utc timestamptz NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_worker_benchmarks_device FOREIGN KEY(worker_device_id) REFERENCES public.worker_devices(id)
);

CREATE TABLE IF NOT EXISTS public.worker_heartbeats (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_device_id uuid NOT NULL,
  sequence_number bigint NOT NULL CONSTRAINT CK_worker_heartbeats_sequence CHECK(sequence_number>0),
  observed_at_utc timestamptz NOT NULL,
  battery_bps int NOT NULL CONSTRAINT CK_worker_heartbeats_battery CHECK(battery_bps BETWEEN 0 AND 10000),
  charging boolean NOT NULL,
  thermal_state varchar(32) NOT NULL CONSTRAINT CK_worker_heartbeats_thermal CHECK(thermal_state IN('nominal','fair','serious','critical')),
  free_ram_bytes bigint NOT NULL CONSTRAINT CK_worker_heartbeats_ram CHECK(free_ram_bytes>=0),
  free_storage_bytes bigint NOT NULL CONSTRAINT CK_worker_heartbeats_storage CHECK(free_storage_bytes>=0),
  network_type varchar(16) NOT NULL CONSTRAINT CK_worker_heartbeats_network CHECK(network_type IN('offline','cellular','wifi','ethernet')),
  current_leases_json jsonb NOT NULL CONSTRAINT CK_worker_heartbeats_leases_json CHECK(jsonb_typeof(current_leases_json::jsonb) IS NOT NULL),
  installed_models_json jsonb NOT NULL CONSTRAINT CK_worker_heartbeats_models_json CHECK(jsonb_typeof(installed_models_json::jsonb) IS NOT NULL),
  received_at_utc timestamptz NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_worker_heartbeats_device FOREIGN KEY(worker_device_id) REFERENCES public.worker_devices(id),
  CONSTRAINT UQ_worker_heartbeat_sequence UNIQUE(worker_device_id,sequence_number)
);

CREATE TABLE IF NOT EXISTS public.device_challenges (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_device_id uuid NULL,
  challenge_hash bytea NOT NULL,
  expires_at_utc timestamptz NOT NULL,
  used_at_utc timestamptz NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_device_challenges_device FOREIGN KEY(worker_device_id) REFERENCES public.worker_devices(id)
);

CREATE TABLE IF NOT EXISTS public.assignments (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  task_attempt_id uuid NOT NULL,
  worker_device_id uuid NOT NULL,
  status varchar(32) NOT NULL CONSTRAINT CK_assignments_status CHECK(status IN ('leased','running','completed','failed','expired','revoked','stale')),
  lease_token_hash bytea NOT NULL,
  fence_token bigint NOT NULL,
  lease_expires_at_utc timestamptz NOT NULL,
  delivery_deadline_at_utc timestamptz NOT NULL,
  start_deadline_at_utc timestamptz NOT NULL,
  assigned_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  started_at_utc timestamptz NULL,
  ended_at_utc timestamptz NULL,
  failure_reason_code varchar(64) NULL,
  start_sequence bigint NULL CONSTRAINT CK_assignments_start_sequence CHECK(start_sequence IS NULL OR start_sequence>0),
  health_snapshot_sequence bigint NULL CONSTRAINT CK_assignments_health_sequence CHECK(health_snapshot_sequence IS NULL OR health_snapshot_sequence>0),
  last_renewal_sequence bigint NOT NULL DEFAULT 0 CONSTRAINT CK_assignments_renewal_sequence CHECK(last_renewal_sequence>=0),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_assignments_attempt_scope FOREIGN KEY(task_attempt_id,workspace_id) REFERENCES public.task_attempts(id,workspace_id),
  CONSTRAINT FK_assignments_device FOREIGN KEY(worker_device_id) REFERENCES public.worker_devices(id),
  CONSTRAINT UQ_assignments_scope UNIQUE(id,workspace_id)
);

CREATE TABLE IF NOT EXISTS public.assignment_checkpoints (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  fence_token bigint NOT NULL,
  checkpoint_uri varchar(1024) NOT NULL,
  checkpoint_sha256 char(64) NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_assignment_checkpoints_scope FOREIGN KEY(assignment_id,workspace_id) REFERENCES public.assignments(id,workspace_id)
);

CREATE TABLE IF NOT EXISTS public.model_downloads (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_device_id uuid NOT NULL,
  model_version_id uuid NOT NULL,
  status varchar(32) NOT NULL,
  bytes_downloaded bigint NOT NULL DEFAULT 0,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_model_downloads_device FOREIGN KEY(worker_device_id) REFERENCES public.worker_devices(id),
  CONSTRAINT FK_model_downloads_version FOREIGN KEY(model_version_id) REFERENCES public.model_versions(id)
);

CREATE TABLE IF NOT EXISTS public.device_model_installs (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_device_id uuid NOT NULL,
  model_version_id uuid NOT NULL,
  verified_sha256 char(64) NOT NULL,
  status varchar(32) NOT NULL,
  verified_at_utc timestamptz NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_device_model_installs_device FOREIGN KEY(worker_device_id) REFERENCES public.worker_devices(id),
  CONSTRAINT FK_device_model_installs_version FOREIGN KEY(model_version_id) REFERENCES public.model_versions(id),
  CONSTRAINT UQ_device_model_install UNIQUE(worker_device_id,model_version_id)
);

CREATE TABLE IF NOT EXISTS public.model_rollouts (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  model_version_id uuid NOT NULL,
  rollout_percent int NOT NULL CONSTRAINT CK_model_rollouts_percent CHECK(rollout_percent BETWEEN 0 AND 100),
  status varchar(32) NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_model_rollouts_version FOREIGN KEY(model_version_id) REFERENCES public.model_versions(id)
);

COMMIT;
