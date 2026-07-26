BEGIN;

CREATE OR REPLACE FUNCTION public.post_ledger_transaction(
  p_workspace_id uuid,
  p_public_id varchar,
  p_idempotency_scope varchar,
  p_idempotency_key varchar,
  p_transaction_type varchar,
  p_currency char(3),
  p_reference_type varchar,
  p_reference_id varchar,
  p_entries jsonb
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_transaction_id uuid;
  v_debit bigint;
  v_credit bigint;
  v_entry_count integer;
  v_distinct_accounts integer;
  v_posted_entry_count integer;
BEGIN
  IF p_workspace_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.workspaces WHERE id = p_workspace_id) THEN
    RAISE EXCEPTION 'LEDGER_WORKSPACE_INVALID';
  END IF;
  IF p_currency <> 'EUR' THEN
    RAISE EXCEPTION 'LEDGER_CURRENCY_UNSUPPORTED';
  END IF;
  IF jsonb_typeof(p_entries) <> 'array' OR jsonb_array_length(p_entries) < 2 THEN
    RAISE EXCEPTION 'LEDGER_INVARIANT_FAILED';
  END IF;

  SELECT
    count(*),
    COALESCE(sum((entry->>'amount_micro_eur')::bigint) FILTER (WHERE entry->>'direction' = 'debit'), 0),
    COALESCE(sum((entry->>'amount_micro_eur')::bigint) FILTER (WHERE entry->>'direction' = 'credit'), 0)
  INTO v_entry_count, v_debit, v_credit
  FROM jsonb_array_elements(p_entries) AS entry
  WHERE entry ? 'account_id'
    AND entry ? 'direction'
    AND entry ? 'amount_micro_eur'
    AND entry->>'direction' IN ('debit', 'credit')
    AND (entry->>'amount_micro_eur')::bigint > 0;

  IF v_entry_count <> jsonb_array_length(p_entries) OR v_debit <> v_credit THEN
    RAISE EXCEPTION 'LEDGER_INVARIANT_FAILED';
  END IF;

  SELECT count(DISTINCT (entry->>'account_id')::uuid)
  INTO v_distinct_accounts
  FROM jsonb_array_elements(p_entries) AS entry;

  IF v_distinct_accounts < 2 THEN
    RAISE EXCEPTION 'LEDGER_REQUIRES_TWO_DISTINCT_ACCOUNTS';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_entries) AS entry
    LEFT JOIN public.ledger_accounts AS account
      ON account.id = (entry->>'account_id')::uuid
     AND account.workspace_id = p_workspace_id
     AND account.currency = p_currency
    WHERE account.id IS NULL
  ) THEN
    RAISE EXCEPTION 'LEDGER_ACCOUNT_INVALID';
  END IF;

  SELECT id INTO v_transaction_id
  FROM public.ledger_transactions
  WHERE workspace_id = p_workspace_id
    AND idempotency_scope = p_idempotency_scope
    AND idempotency_key = p_idempotency_key;

  IF v_transaction_id IS NOT NULL THEN
    RETURN v_transaction_id;
  END IF;

  v_transaction_id := uuidv7();
  INSERT INTO public.ledger_transactions(
    id, workspace_id, public_id, idempotency_scope, idempotency_key, transaction_type,
    currency, reference_type, reference_id, posted_at_utc
  ) VALUES (
    v_transaction_id, p_workspace_id, p_public_id, p_idempotency_scope, p_idempotency_key,
    p_transaction_type, p_currency, p_reference_type, p_reference_id, CURRENT_TIMESTAMP
  )
  ON CONFLICT (workspace_id, idempotency_scope, idempotency_key) DO NOTHING;

  IF NOT FOUND THEN
    SELECT id INTO v_transaction_id
    FROM public.ledger_transactions
    WHERE workspace_id = p_workspace_id
      AND idempotency_scope = p_idempotency_scope
      AND idempotency_key = p_idempotency_key;
    RETURN v_transaction_id;
  END IF;

  INSERT INTO public.ledger_entries(workspace_id, transaction_id, account_id, amount_micro_eur, created_at_utc)
  SELECT
    p_workspace_id,
    v_transaction_id,
    (entry->>'account_id')::uuid,
    sum(
      CASE entry->>'direction'
        WHEN 'debit' THEN (entry->>'amount_micro_eur')::bigint
        ELSE -((entry->>'amount_micro_eur')::bigint)
      END
    ),
    CURRENT_TIMESTAMP
  FROM jsonb_array_elements(p_entries) AS entry
  GROUP BY (entry->>'account_id')::uuid
  HAVING sum(
    CASE entry->>'direction'
      WHEN 'debit' THEN (entry->>'amount_micro_eur')::bigint
      ELSE -((entry->>'amount_micro_eur')::bigint)
    END
  ) <> 0;

  GET DIAGNOSTICS v_posted_entry_count = ROW_COUNT;
  IF v_posted_entry_count < 2 THEN
    RAISE EXCEPTION 'LEDGER_REQUIRES_TWO_POSTED_ENTRIES';
  END IF;

  IF (
    SELECT COALESCE(sum(amount_micro_eur), 0)
    FROM public.ledger_entries
    WHERE workspace_id = p_workspace_id AND transaction_id = v_transaction_id
  ) <> 0 THEN
    RAISE EXCEPTION 'LEDGER_INVARIANT_FAILED';
  END IF;

  RETURN v_transaction_id;
END
$$;

CREATE OR REPLACE FUNCTION eventing.claim_outbox_batch(
  p_owner text,
  p_batch_size integer,
  p_lease_seconds integer,
  p_max_attempts integer
) RETURNS SETOF public.outbox_events
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_batch_size <= 0 OR p_lease_seconds <= 0 OR p_max_attempts <= 0 THEN
    RAISE EXCEPTION 'OUTBOX_CLAIM_ARGUMENT_INVALID';
  END IF;

  RETURN QUERY
  WITH candidates AS (
    SELECT event.id
    FROM public.outbox_events AS event
    WHERE event.status IN ('pending', 'retry')
      AND event.available_at_utc <= CURRENT_TIMESTAMP
      AND event.attempt_count < p_max_attempts
      AND (event.lease_expires_at_utc IS NULL OR event.lease_expires_at_utc < CURRENT_TIMESTAMP)
    ORDER BY event.available_at_utc, event.created_at_utc, event.id
    FOR UPDATE SKIP LOCKED
    LIMIT p_batch_size
  ), claimed AS (
    UPDATE public.outbox_events AS event
    SET status = 'leased',
        lease_owner = p_owner,
        lease_expires_at_utc = CURRENT_TIMESTAMP + make_interval(secs => p_lease_seconds),
        attempt_count = event.attempt_count + 1
    FROM candidates
    WHERE event.id = candidates.id
    RETURNING event.*
  )
  SELECT * FROM claimed;
END
$$;

CREATE OR REPLACE FUNCTION eventing.claim_websocket_deliveries(
  p_owner text,
  p_connection_id uuid,
  p_batch_size integer,
  p_lease_seconds integer,
  p_max_in_flight integer
) RETURNS TABLE(delivery_id uuid, delivery_sequence bigint, cloud_event_json jsonb)
LANGUAGE plpgsql
AS $$
DECLARE
  v_in_flight integer;
  v_remaining integer;
BEGIN
  IF p_batch_size <= 0 OR p_lease_seconds <= 0 OR p_max_in_flight <= 0 THEN
    RAISE EXCEPTION 'DELIVERY_CLAIM_ARGUMENT_INVALID';
  END IF;

  SELECT count(*) INTO v_in_flight
  FROM public.websocket_deliveries AS delivery
  JOIN public.websocket_subscriptions AS subscription ON subscription.id = delivery.subscription_id
  WHERE subscription.connection_id = p_connection_id
    AND delivery.status IN ('leased', 'sent');

  v_remaining := GREATEST(0, p_max_in_flight - v_in_flight);
  IF v_remaining = 0 THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH available AS (
    SELECT delivery.id
    FROM public.websocket_deliveries AS delivery
    JOIN public.websocket_subscriptions AS subscription ON subscription.id = delivery.subscription_id
    WHERE subscription.connection_id = p_connection_id
      AND subscription.status = 'active'
      AND delivery.status IN ('pending', 'retry')
      AND delivery.available_at_utc <= CURRENT_TIMESTAMP
      AND (delivery.lease_expires_at_utc IS NULL OR delivery.lease_expires_at_utc < CURRENT_TIMESTAMP)
    ORDER BY delivery.delivery_sequence, delivery.id
    FOR UPDATE OF delivery SKIP LOCKED
    LIMIT LEAST(p_batch_size, v_remaining)
  ), claimed AS (
    UPDATE public.websocket_deliveries AS delivery
    SET status = 'leased',
        lease_owner = p_owner,
        lease_expires_at_utc = CURRENT_TIMESTAMP + make_interval(secs => p_lease_seconds),
        attempt_count = delivery.attempt_count + 1
    FROM available
    WHERE delivery.id = available.id
    RETURNING delivery.*
  )
  SELECT claimed.id, claimed.delivery_sequence, event.cloud_event_json
  FROM claimed
  JOIN public.outbox_events AS event ON event.id = claimed.outbox_event_id;
END
$$;

CREATE OR REPLACE FUNCTION eventing.acknowledge_delivery(
  p_delivery_id uuid,
  p_sequence bigint,
  p_principal_id uuid
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_subscription_id uuid;
  v_expected_principal_id uuid;
BEGIN
  UPDATE public.websocket_deliveries AS delivery
  SET status = 'acknowledged',
      acknowledged_at_utc = CURRENT_TIMESTAMP,
      lease_owner = NULL,
      lease_expires_at_utc = NULL
  WHERE delivery.id = p_delivery_id
    AND delivery.delivery_sequence = p_sequence
    AND delivery.status IN ('leased', 'sent')
  RETURNING delivery.subscription_id INTO v_subscription_id;

  IF v_subscription_id IS NULL THEN
    RAISE EXCEPTION 'DELIVERY_ACK_INVALID';
  END IF;

  SELECT subscription.principal_id INTO v_expected_principal_id
  FROM public.websocket_subscriptions AS subscription
  WHERE subscription.id = v_subscription_id
  FOR UPDATE;

  IF v_expected_principal_id IS DISTINCT FROM p_principal_id THEN
    RAISE EXCEPTION 'DELIVERY_ACK_PRINCIPAL_MISMATCH';
  END IF;

  INSERT INTO public.websocket_acknowledgements(
    id, delivery_id, subscription_id, delivery_sequence, principal_id, acknowledged_at_utc
  ) VALUES (
    uuidv7(), p_delivery_id, v_subscription_id, p_sequence, p_principal_id, CURRENT_TIMESTAMP
  )
  ON CONFLICT (delivery_id) DO NOTHING;

  UPDATE public.websocket_subscriptions
  SET last_acknowledged_sequence = GREATEST(last_acknowledged_sequence, p_sequence),
      next_sequence = GREATEST(next_sequence, p_sequence + 1)
  WHERE id = v_subscription_id;
END
$$;

CREATE OR REPLACE FUNCTION eventing.open_websocket_connection(
  p_public_id varchar,
  p_principal_id uuid,
  p_workspace_id uuid,
  p_client_id varchar,
  p_client_version varchar,
  p_resume_token_hash bytea,
  p_resume_expires_at_utc timestamptz,
  p_relay_instance_id varchar,
  p_owner_lease_seconds integer
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_connection_id uuid := uuidv7();
BEGIN
  IF p_owner_lease_seconds <= 0 OR octet_length(p_resume_token_hash) <> 32 THEN
    RAISE EXCEPTION 'WEBSOCKET_CONNECTION_ARGUMENT_INVALID';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.principals WHERE id = p_principal_id) THEN
    RAISE EXCEPTION 'WEBSOCKET_PRINCIPAL_INVALID';
  END IF;
  IF p_workspace_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.workspaces AS workspace
    JOIN public.workspace_members AS membership
      ON membership.workspace_id = workspace.id
     AND membership.principal_id = p_principal_id
    WHERE workspace.id = p_workspace_id
      AND workspace.status = 'active'
  ) THEN
    RAISE EXCEPTION 'WEBSOCKET_WORKSPACE_ACCESS_DENIED';
  END IF;

  INSERT INTO public.websocket_connections(
    id, public_id, principal_id, workspace_id, client_id, client_version,
    resume_token_hash, resume_expires_at_utc, relay_instance_id,
    owner_lease_expires_at_utc, connected_at_utc, last_heartbeat_at_utc, status
  ) VALUES (
    v_connection_id, p_public_id, p_principal_id, p_workspace_id, p_client_id, p_client_version,
    p_resume_token_hash, p_resume_expires_at_utc, p_relay_instance_id,
    CURRENT_TIMESTAMP + make_interval(secs => p_owner_lease_seconds),
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'connected'
  );
  RETURN v_connection_id;
END
$$;

CREATE OR REPLACE FUNCTION eventing.create_websocket_subscription(
  p_public_id varchar,
  p_connection_id uuid,
  p_principal_id uuid,
  p_workspace_id uuid,
  p_event_types jsonb
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_subscription_id uuid := uuidv7();
BEGIN
  IF jsonb_typeof(p_event_types) <> 'array' OR jsonb_array_length(p_event_types) = 0 THEN
    RAISE EXCEPTION 'WEBSOCKET_SUBSCRIPTION_EVENTS_INVALID';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.websocket_connections
    WHERE id = p_connection_id
      AND principal_id = p_principal_id
      AND workspace_id IS NOT DISTINCT FROM p_workspace_id
      AND status = 'connected'
      AND owner_lease_expires_at_utc > CURRENT_TIMESTAMP
  ) THEN
    RAISE EXCEPTION 'WEBSOCKET_CONNECTION_INVALID';
  END IF;

  INSERT INTO public.websocket_subscriptions(
    id, public_id, connection_id, principal_id, workspace_id,
    event_types_json, next_sequence, last_acknowledged_sequence, status, created_at_utc
  ) VALUES (
    v_subscription_id, p_public_id, p_connection_id, p_principal_id, p_workspace_id,
    p_event_types, 1, 0, 'active', CURRENT_TIMESTAMP
  );
  RETURN v_subscription_id;
END
$$;

CREATE OR REPLACE FUNCTION eventing.mark_websocket_delivery_sent(
  p_delivery_id uuid,
  p_lease_owner text,
  p_ack_timeout_seconds integer
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_ack_timeout_seconds <= 0 THEN
    RAISE EXCEPTION 'DELIVERY_SENT_ARGUMENT_INVALID';
  END IF;
  UPDATE public.websocket_deliveries
  SET status = 'sent',
      sent_at_utc = CURRENT_TIMESTAMP,
      ack_deadline_at_utc = CURRENT_TIMESTAMP + make_interval(secs => p_ack_timeout_seconds)
  WHERE id = p_delivery_id
    AND status = 'leased'
    AND lease_owner = p_lease_owner
    AND lease_expires_at_utc > CURRENT_TIMESTAMP;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'DELIVERY_SENT_TRANSITION_INVALID';
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION eventing.touch_websocket_connection(
  p_connection_id uuid,
  p_relay_instance_id text,
  p_owner_lease_seconds integer
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.websocket_connections
  SET last_heartbeat_at_utc = CURRENT_TIMESTAMP,
      owner_lease_expires_at_utc = CURRENT_TIMESTAMP + make_interval(secs => p_owner_lease_seconds)
  WHERE id = p_connection_id
    AND relay_instance_id = p_relay_instance_id
    AND status = 'connected';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'WEBSOCKET_CONNECTION_OWNERSHIP_LOST';
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION eventing.close_websocket_connection(
  p_connection_id uuid,
  p_relay_instance_id text
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.websocket_connections
  SET status = 'disconnected', disconnected_at_utc = CURRENT_TIMESTAMP
  WHERE id = p_connection_id
    AND relay_instance_id = p_relay_instance_id
    AND status = 'connected';
  UPDATE public.websocket_subscriptions
  SET status = 'expired'
  WHERE connection_id = p_connection_id AND status = 'active';
END
$$;

CREATE OR REPLACE FUNCTION public.select_next_routable_attempt(
  p_router_instance_id text,
  p_claim_seconds integer,
  p_candidate_window integer
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_attempt_id uuid;
  v_workspace_id uuid;
BEGIN
  IF p_claim_seconds <= 0 OR p_candidate_window <= 0 THEN
    RAISE EXCEPTION 'ROUTING_CLAIM_ARGUMENT_INVALID';
  END IF;

  WITH candidate_window AS (
    SELECT attempt.id, attempt.workspace_id,
           CASE WHEN EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - task.submitted_at_utc)) >= 300 THEN 0 ELSE 1 END AS stale_rank,
           COALESCE(fairness.deficit_units, 0) AS deficit_units,
           task.priority_bps, task.deadline_at_utc, task.submitted_at_utc, task.id AS task_id
    FROM public.task_attempts AS attempt
    JOIN public.tasks AS task
      ON task.id = attempt.task_id AND task.workspace_id = attempt.workspace_id
    LEFT JOIN public.workspace_routing_fairness AS fairness
      ON fairness.workspace_id = attempt.workspace_id
    WHERE attempt.status = 'matching'
      AND task.lifecycle_status IN ('admitted', 'queued')
      AND (attempt.routing_claim_expires_at_utc IS NULL OR attempt.routing_claim_expires_at_utc < CURRENT_TIMESTAMP)
    ORDER BY task.submitted_at_utc, task.id, attempt.id
    LIMIT p_candidate_window
  )
  SELECT attempt.id, attempt.workspace_id
  INTO v_attempt_id, v_workspace_id
  FROM public.task_attempts AS attempt
  JOIN candidate_window AS candidate ON candidate.id = attempt.id
  ORDER BY candidate.stale_rank,
           candidate.deficit_units DESC,
           candidate.priority_bps DESC,
           candidate.deadline_at_utc NULLS LAST,
           candidate.submitted_at_utc,
           candidate.task_id,
           candidate.id
  FOR UPDATE OF attempt SKIP LOCKED
  LIMIT 1;

  IF v_attempt_id IS NOT NULL THEN
    UPDATE public.task_attempts
    SET routing_claim_owner = p_router_instance_id,
        routing_claim_expires_at_utc = CURRENT_TIMESTAMP + make_interval(secs => p_claim_seconds)
    WHERE id = v_attempt_id;

    INSERT INTO public.workspace_routing_fairness(workspace_id, deficit_units, consecutive_assignments, last_selected_at_utc, updated_at_utc)
    VALUES(v_workspace_id, -1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT (workspace_id) DO UPDATE
    SET deficit_units = GREATEST(-100000, public.workspace_routing_fairness.deficit_units - 1),
        consecutive_assignments = public.workspace_routing_fairness.consecutive_assignments + 1,
        last_selected_at_utc = CURRENT_TIMESTAMP,
        updated_at_utc = CURRENT_TIMESTAMP,
        row_version = public.workspace_routing_fairness.row_version + 1;

    UPDATE public.workspace_routing_fairness
    SET deficit_units = LEAST(100000, deficit_units + 1),
        consecutive_assignments = 0,
        updated_at_utc = CURRENT_TIMESTAMP,
        row_version = row_version + 1
    WHERE workspace_id <> v_workspace_id;
  END IF;

  RETURN v_attempt_id;
END
$$;

COMMIT;
