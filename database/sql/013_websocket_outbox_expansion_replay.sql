BEGIN;

CREATE OR REPLACE FUNCTION eventing.expand_outbox_batch(
  p_owner text,
  p_batch_size integer,
  p_lease_seconds integer,
  p_max_attempts integer
) RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_event public.outbox_events%ROWTYPE;
  v_subscription_id uuid;
  v_sequence bigint;
  v_expanded integer := 0;
BEGIN
  FOR v_event IN
    SELECT * FROM eventing.claim_outbox_batch(
      p_owner, p_batch_size, p_lease_seconds, p_max_attempts
    )
  LOOP
    FOR v_subscription_id IN
      SELECT subscription.id
      FROM public.websocket_subscriptions AS subscription
      WHERE subscription.status IN ('active', 'paused', 'expired')
        AND subscription.workspace_id IS NOT DISTINCT FROM v_event.workspace_id
        AND (
          subscription.event_types_json ? '*' OR
          subscription.event_types_json ? v_event.event_type OR
          subscription.event_types_json ? COALESCE(v_event.cloud_event_json->>'type', '')
        )
        AND (
          NOT (v_event.cloud_event_json->'data' ? 'workerDeviceId') OR
          EXISTS (
            SELECT 1
            FROM public.worker_devices AS device
            JOIN public.workers AS worker ON worker.id = device.worker_id
            WHERE device.id = (v_event.cloud_event_json->'data'->>'workerDeviceId')::uuid
              AND worker.principal_id = subscription.principal_id
          )
        )
      ORDER BY subscription.id
      FOR UPDATE
    LOOP
      UPDATE public.websocket_subscriptions
      SET next_sequence = next_sequence + 1
      WHERE id = v_subscription_id
      RETURNING next_sequence - 1 INTO v_sequence;

      INSERT INTO public.websocket_deliveries(
        id, subscription_id, outbox_event_id, delivery_sequence, status,
        available_at_utc, attempt_count, created_at_utc
      ) VALUES (
        uuidv7(), v_subscription_id, v_event.id, v_sequence, 'pending',
        CURRENT_TIMESTAMP, 0, CURRENT_TIMESTAMP
      )
      ON CONFLICT (subscription_id, outbox_event_id) DO NOTHING;
    END LOOP;

    UPDATE public.outbox_events
    SET status = 'expanded', published_at_utc = CURRENT_TIMESTAMP,
        lease_owner = NULL, lease_expires_at_utc = NULL
    WHERE id = v_event.id AND status = 'leased' AND lease_owner = p_owner;
    v_expanded := v_expanded + 1;
  END LOOP;
  RETURN v_expanded;
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

  UPDATE public.websocket_deliveries AS delivery
  SET status = 'retry', lease_owner = NULL, lease_expires_at_utc = NULL,
      available_at_utc = CURRENT_TIMESTAMP, last_error_code = 'ACK_TIMEOUT'
  FROM public.websocket_subscriptions AS subscription
  WHERE subscription.connection_id = p_connection_id
    AND subscription.id = delivery.subscription_id
    AND (
      (delivery.status = 'leased' AND delivery.lease_expires_at_utc < CURRENT_TIMESTAMP) OR
      (delivery.status = 'sent' AND delivery.ack_deadline_at_utc < CURRENT_TIMESTAMP)
    );

  SELECT count(*) INTO v_in_flight
  FROM public.websocket_deliveries AS delivery
  JOIN public.websocket_subscriptions AS subscription ON subscription.id = delivery.subscription_id
  WHERE subscription.connection_id = p_connection_id
    AND delivery.status IN ('leased', 'sent');

  v_remaining := GREATEST(0, p_max_in_flight - v_in_flight);
  IF v_remaining = 0 THEN RETURN; END IF;

  RETURN QUERY
  WITH available AS (
    SELECT delivery.id
    FROM public.websocket_deliveries AS delivery
    JOIN public.websocket_subscriptions AS subscription ON subscription.id = delivery.subscription_id
    WHERE subscription.connection_id = p_connection_id
      AND subscription.status = 'active'
      AND delivery.status IN ('pending', 'retry')
      AND delivery.available_at_utc <= CURRENT_TIMESTAMP
    ORDER BY delivery.delivery_sequence, delivery.id
    FOR UPDATE OF delivery SKIP LOCKED
    LIMIT LEAST(p_batch_size, v_remaining)
  ), claimed AS (
    UPDATE public.websocket_deliveries AS delivery
    SET status = 'leased', lease_owner = p_owner,
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

ALTER FUNCTION eventing.expand_outbox_batch(text, integer, integer, integer)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION eventing.expand_outbox_batch(text, integer, integer, integer)
  SECURITY DEFINER SET search_path = pg_catalog, public, eventing;
REVOKE ALL ON FUNCTION eventing.expand_outbox_batch(text, integer, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eventing.expand_outbox_batch(text, integer, integer, integer) TO edgemint_runtime;

COMMIT;
