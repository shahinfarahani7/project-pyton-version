BEGIN;

CREATE TABLE IF NOT EXISTS public.outbox_events (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NULL,
  event_type varchar(200) NOT NULL,
  aggregate_type varchar(100) NOT NULL,
  aggregate_id varchar(128) NOT NULL,
  aggregate_sequence bigint NOT NULL,
  cloud_event_json jsonb NOT NULL CONSTRAINT CK_outbox_events_json CHECK(jsonb_typeof(cloud_event_json::jsonb) IS NOT NULL),
  status varchar(24) NOT NULL DEFAULT 'pending' CONSTRAINT CK_outbox_status CHECK(status IN('pending','retry','leased','expanded','dead_letter')),
  available_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  lease_owner varchar(128) NULL,
  lease_expires_at_utc timestamptz NULL,
  published_at_utc timestamptz NULL,
  attempt_count int NOT NULL DEFAULT 0 CONSTRAINT CK_outbox_attempt_count CHECK(attempt_count>=0),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT CK_outbox_aggregate_sequence CHECK(aggregate_sequence>0),
  CONSTRAINT UQ_outbox_aggregate_sequence UNIQUE(aggregate_type,aggregate_id,aggregate_sequence)
);

CREATE TABLE IF NOT EXISTS public.inbox_events (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  consumer_name varchar(128) NOT NULL,
  event_id uuid NOT NULL,
  event_type varchar(200) NOT NULL,
  payload_sha256 char(64) NOT NULL,
  processed_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT UQ_inbox_consumer_event UNIQUE(consumer_name,event_id)
);

CREATE TABLE IF NOT EXISTS public.websocket_connections (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  public_id varchar(32) NOT NULL UNIQUE,
  principal_id uuid NOT NULL,
  workspace_id uuid NULL,
  client_id varchar(128) NOT NULL,
  client_version varchar(64) NOT NULL,
  resume_token_hash bytea NOT NULL,
  resume_expires_at_utc timestamptz NOT NULL,
  relay_instance_id varchar(128) NOT NULL,
  owner_lease_expires_at_utc timestamptz NOT NULL,
  connected_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_heartbeat_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  disconnected_at_utc timestamptz NULL,
  status varchar(24) NOT NULL CONSTRAINT CK_ws_connection_status CHECK(status IN('connected','disconnected')),
  CONSTRAINT FK_websocket_connections_principal FOREIGN KEY(principal_id) REFERENCES public.principals(id),
  CONSTRAINT FK_websocket_connections_workspace FOREIGN KEY(workspace_id) REFERENCES public.workspaces(id)
);

CREATE TABLE IF NOT EXISTS public.websocket_subscriptions (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  public_id varchar(32) NOT NULL UNIQUE,
  connection_id uuid NOT NULL,
  principal_id uuid NOT NULL,
  workspace_id uuid NULL,
  event_types_json jsonb NOT NULL CONSTRAINT CK_ws_subscriptions_json CHECK(jsonb_typeof(event_types_json::jsonb) IS NOT NULL),
  next_sequence bigint NOT NULL DEFAULT 1,
  last_acknowledged_sequence bigint NOT NULL DEFAULT 0,
  status varchar(24) NOT NULL CONSTRAINT CK_ws_subscription_status CHECK(status IN('active','paused','expired')),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_ws_subscriptions_connection FOREIGN KEY(connection_id) REFERENCES public.websocket_connections(id),
  CONSTRAINT FK_ws_subscriptions_principal FOREIGN KEY(principal_id) REFERENCES public.principals(id),
  CONSTRAINT FK_ws_subscriptions_workspace FOREIGN KEY(workspace_id) REFERENCES public.workspaces(id),
  CONSTRAINT CK_ws_subscription_sequence CHECK(next_sequence>last_acknowledged_sequence)
);

CREATE TABLE IF NOT EXISTS public.websocket_deliveries (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  subscription_id uuid NOT NULL,
  outbox_event_id uuid NOT NULL,
  delivery_sequence bigint NOT NULL,
  status varchar(24) NOT NULL DEFAULT 'pending' CONSTRAINT CK_ws_delivery_status CHECK(status IN('pending','retry','leased','sent','acknowledged','dead_letter')),
  available_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  lease_owner varchar(128) NULL,
  lease_expires_at_utc timestamptz NULL,
  ack_deadline_at_utc timestamptz NULL,
  attempt_count int NOT NULL DEFAULT 0 CONSTRAINT CK_ws_delivery_attempt_count CHECK(attempt_count>=0),
  sent_at_utc timestamptz NULL,
  acknowledged_at_utc timestamptz NULL,
  last_error_code varchar(64) NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_ws_deliveries_subscription FOREIGN KEY(subscription_id) REFERENCES public.websocket_subscriptions(id),
  CONSTRAINT FK_ws_deliveries_outbox FOREIGN KEY(outbox_event_id) REFERENCES public.outbox_events(id),
  CONSTRAINT CK_ws_delivery_sequence CHECK(delivery_sequence>0),
  CONSTRAINT UQ_ws_delivery_event UNIQUE(subscription_id,outbox_event_id),
  CONSTRAINT UQ_ws_delivery_sequence UNIQUE(subscription_id,delivery_sequence)
);

CREATE TABLE IF NOT EXISTS public.websocket_acknowledgements (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  delivery_id uuid NOT NULL,
  subscription_id uuid NOT NULL,
  delivery_sequence bigint NOT NULL,
  principal_id uuid NOT NULL,
  acknowledged_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_ws_ack_delivery FOREIGN KEY(delivery_id) REFERENCES public.websocket_deliveries(id),
  CONSTRAINT FK_ws_ack_subscription FOREIGN KEY(subscription_id) REFERENCES public.websocket_subscriptions(id),
  CONSTRAINT FK_ws_ack_principal FOREIGN KEY(principal_id) REFERENCES public.principals(id),
  CONSTRAINT UQ_ws_ack_delivery UNIQUE(delivery_id)
);

CREATE TABLE IF NOT EXISTS public.event_dead_letters (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  delivery_id uuid NOT NULL,
  outbox_event_id uuid NOT NULL,
  failure_code varchar(64) NOT NULL,
  failure_detail varchar(2000) NOT NULL,
  payload_sha256 char(64) NOT NULL,
  dead_lettered_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at_utc timestamptz NOT NULL,
  replay_cycle int NOT NULL DEFAULT 1 CONSTRAINT CK_event_dlq_replay_cycle CHECK(replay_cycle>0),
  replay_status varchar(24) NOT NULL DEFAULT 'not_requested' CONSTRAINT CK_event_dlq_replay_status CHECK(replay_status IN('not_requested','replayed')),
  replay_requested_by varchar(255) NULL,
  replay_reason varchar(500) NULL,
  replayed_at_utc timestamptz NULL,
  CONSTRAINT FK_event_dlq_delivery FOREIGN KEY(delivery_id) REFERENCES public.websocket_deliveries(id),
  CONSTRAINT FK_event_dlq_outbox FOREIGN KEY(outbox_event_id) REFERENCES public.outbox_events(id),
  CONSTRAINT UQ_event_dlq_delivery_cycle UNIQUE(delivery_id,replay_cycle)
);

CREATE TABLE IF NOT EXISTS public.outbox_dead_letters (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  outbox_event_id uuid NOT NULL,
  failure_code varchar(64) NOT NULL,
  failure_detail varchar(2000) NOT NULL,
  payload_sha256 char(64) NOT NULL,
  dead_lettered_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at_utc timestamptz NOT NULL,
  replay_cycle int NOT NULL DEFAULT 1 CONSTRAINT CK_outbox_dlq_replay_cycle CHECK(replay_cycle>0),
  replay_status varchar(24) NOT NULL DEFAULT 'not_requested' CONSTRAINT CK_outbox_dlq_replay_status CHECK(replay_status IN('not_requested','replayed')),
  replay_requested_by varchar(255) NULL,
  replay_reason varchar(500) NULL,
  replayed_at_utc timestamptz NULL,
  CONSTRAINT FK_outbox_dlq_event FOREIGN KEY(outbox_event_id) REFERENCES public.outbox_events(id),
  CONSTRAINT UQ_outbox_dlq_event_cycle UNIQUE(outbox_event_id,replay_cycle)
);

CREATE TABLE IF NOT EXISTS public.event_consumer_offsets (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  consumer_name varchar(128) NOT NULL,
  subscription_key varchar(200) NOT NULL,
  last_acknowledged_sequence bigint NOT NULL DEFAULT 0,
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT UQ_event_consumer_offset UNIQUE(consumer_name,subscription_key)
);

CREATE TABLE IF NOT EXISTS public.browser_sessions (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  public_id varchar(32) NOT NULL UNIQUE,
  principal_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  session_token_hash bytea NOT NULL,
  csrf_secret_hash bytea NOT NULL,
  authorization_generation bigint NOT NULL DEFAULT 1,
  risk_state varchar(32) NOT NULL DEFAULT 'normal' CONSTRAINT CK_browser_sessions_risk_state CHECK(risk_state IN('normal','step_up_required','locked')),
  absolute_expires_at_utc timestamptz NOT NULL,
  idle_expires_at_utc timestamptz NOT NULL,
  last_seen_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revoked_at_utc timestamptz NULL,
  revocation_reason varchar(256) NULL,
  rotated_from_session_id uuid NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  row_version bigint DEFAULT 0 NOT NULL,
  CONSTRAINT FK_browser_sessions_principal FOREIGN KEY(principal_id) REFERENCES public.principals(id),
  CONSTRAINT FK_browser_sessions_workspace FOREIGN KEY(workspace_id) REFERENCES public.workspaces(id),
  CONSTRAINT FK_browser_sessions_rotated_from FOREIGN KEY(rotated_from_session_id) REFERENCES public.browser_sessions(id),
  CONSTRAINT CK_browser_sessions_expiry CHECK(idle_expires_at_utc<=absolute_expires_at_utc)
);

CREATE TABLE IF NOT EXISTS public.system_audit_events (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  actor_id varchar(255) NOT NULL,
  action varchar(128) NOT NULL,
  resource_type varchar(128) NOT NULL,
  resource_id varchar(128) NOT NULL,
  details_json jsonb NOT NULL CONSTRAINT CK_system_audit_events_json CHECK(jsonb_typeof(details_json::jsonb) IS NOT NULL),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS public.delegated_token_jtis (
  jti_hash bytea NOT NULL PRIMARY KEY,
  principal_id uuid NOT NULL,
  workspace_id uuid NULL,
  expires_at_utc timestamptz NOT NULL,
  consumed_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_delegated_token_jtis_principal FOREIGN KEY(principal_id) REFERENCES public.principals(id)
);

COMMIT;
