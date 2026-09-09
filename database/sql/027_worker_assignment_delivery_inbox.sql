-- Assignment delivery inbox for poll/ACK/bootstrap path (Architecture v2 §7, §39, A03, T03).

BEGIN;

CREATE TABLE IF NOT EXISTS public.worker_assignment_deliveries (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  worker_device_id uuid NOT NULL,
  fence_token bigint NOT NULL CONSTRAINT CK_worker_assignment_deliveries_fence CHECK (fence_token > 0),
  delivery_channel varchar(32) NOT NULL DEFAULT 'poll'
    CONSTRAINT CK_worker_assignment_deliveries_channel
    CHECK (delivery_channel IN ('poll', 'websocket')),
  inbox_recorded_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ack_received_at_utc timestamptz NULL,
  ack_sequence int NULL CONSTRAINT CK_worker_assignment_deliveries_ack_sequence CHECK (ack_sequence IS NULL OR ack_sequence > 0),
  bootstrap_generation bigint NOT NULL DEFAULT 1
    CONSTRAINT CK_worker_assignment_deliveries_generation CHECK (bootstrap_generation > 0),
  CONSTRAINT FK_worker_assignment_deliveries_assignment_scope
    FOREIGN KEY (assignment_id, workspace_id) REFERENCES public.assignments (id, workspace_id),
  CONSTRAINT FK_worker_assignment_deliveries_device
    FOREIGN KEY (worker_device_id) REFERENCES public.worker_devices (id),
  CONSTRAINT UQ_worker_assignment_deliveries_identity
    UNIQUE (assignment_id, worker_device_id, fence_token)
);

CREATE INDEX IF NOT EXISTS IX_worker_assignment_deliveries_device_unacked
  ON public.worker_assignment_deliveries (worker_device_id, inbox_recorded_at_utc DESC)
  WHERE ack_received_at_utc IS NULL;

CREATE OR REPLACE FUNCTION public.record_worker_assignment_delivery(
  p_workspace_id uuid,
  p_assignment_id uuid,
  p_worker_device_id uuid,
  p_fence_token bigint,
  p_delivery_channel text DEFAULT 'poll'
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_delivery_id uuid;
BEGIN
  IF p_fence_token <= 0 THEN
    RAISE EXCEPTION 'ASSIGNMENT_DELIVERY_ARGUMENT_INVALID';
  END IF;
  IF p_delivery_channel NOT IN ('poll', 'websocket') THEN
    RAISE EXCEPTION 'ASSIGNMENT_DELIVERY_ARGUMENT_INVALID';
  END IF;

  INSERT INTO public.worker_assignment_deliveries(
    workspace_id, assignment_id, worker_device_id, fence_token, delivery_channel
  )
  VALUES (
    p_workspace_id, p_assignment_id, p_worker_device_id, p_fence_token, p_delivery_channel
  )
  ON CONFLICT (assignment_id, worker_device_id, fence_token) DO NOTHING
  RETURNING id INTO v_delivery_id;

  IF v_delivery_id IS NOT NULL THEN
    RETURN v_delivery_id;
  END IF;

  SELECT id
  INTO v_delivery_id
  FROM public.worker_assignment_deliveries
  WHERE assignment_id = p_assignment_id
    AND worker_device_id = p_worker_device_id
    AND fence_token = p_fence_token;

  RETURN v_delivery_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.acknowledge_worker_assignment_delivery(
  p_assignment_id uuid,
  p_worker_device_id uuid,
  p_fence_token bigint,
  p_ack_sequence int DEFAULT 1
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated int;
BEGIN
  IF p_ack_sequence <= 0 THEN
    RAISE EXCEPTION 'ASSIGNMENT_DELIVERY_ARGUMENT_INVALID';
  END IF;

  UPDATE public.worker_assignment_deliveries
  SET ack_received_at_utc = CURRENT_TIMESTAMP,
      ack_sequence = p_ack_sequence
  WHERE assignment_id = p_assignment_id
    AND worker_device_id = p_worker_device_id
    AND fence_token = p_fence_token
    AND ack_received_at_utc IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 1 THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.worker_assignment_deliveries
    WHERE assignment_id = p_assignment_id
      AND worker_device_id = p_worker_device_id
      AND fence_token = p_fence_token
      AND ack_received_at_utc IS NOT NULL
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

COMMENT ON TABLE public.worker_assignment_deliveries IS
  'Durable assignment delivery inbox for poll/WebSocket transport (v2 §7, §39).';

COMMENT ON FUNCTION public.record_worker_assignment_delivery IS
  'Idempotent delivery record before worker-side processing/ACK.';

COMMENT ON FUNCTION public.acknowledge_worker_assignment_delivery IS
  'Transport receipt ACK; duplicate ACK returns true without side effects.';

COMMIT;
