-- Assignment transport recovery receipts (v2 §2.4, A09, T09).


BEGIN;
CREATE TABLE IF NOT EXISTS public.assignment_transport_receipts (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  workspace_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  event_kind varchar(32) NOT NULL
    CONSTRAINT CK_assignment_transport_event_kind
    CHECK (event_kind IN ('ack', 'progress', 'checkpoint', 'result')),
  event_identity varchar(255) NOT NULL,
  payload_digest char(64) NOT NULL,
  aggregate_sequence bigint NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_assignment_transport_assignment
    FOREIGN KEY (assignment_id) REFERENCES public.assignments (id),
  CONSTRAINT UQ_assignment_transport_identity
    UNIQUE (assignment_id, event_kind, event_identity)
);

CREATE INDEX IF NOT EXISTS IX_assignment_transport_workspace
  ON public.assignment_transport_receipts (workspace_id, assignment_id, created_at_utc DESC);

CREATE OR REPLACE FUNCTION public.record_assignment_transport_receipt(
  p_workspace_id uuid,
  p_assignment_id uuid,
  p_event_kind text,
  p_event_identity text,
  p_payload_digest char(64),
  p_aggregate_sequence bigint
) RETURNS TABLE (
  is_new boolean,
  conflict boolean,
  stored_aggregate_sequence bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
  v_existing_digest char(64);
  v_existing_sequence bigint;
BEGIN
  IF p_event_kind NOT IN ('ack', 'progress', 'checkpoint', 'result') THEN
    RAISE EXCEPTION 'invalid transport event kind: %', p_event_kind;
  END IF;

  INSERT INTO public.assignment_transport_receipts (
    workspace_id, assignment_id, event_kind, event_identity,
    payload_digest, aggregate_sequence
  ) VALUES (
    p_workspace_id, p_assignment_id, p_event_kind, p_event_identity,
    p_payload_digest, p_aggregate_sequence
  )
  ON CONFLICT ON CONSTRAINT UQ_assignment_transport_identity DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NOT NULL THEN
    is_new := TRUE;
    conflict := FALSE;
    stored_aggregate_sequence := p_aggregate_sequence;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT atr.payload_digest, atr.aggregate_sequence
  INTO v_existing_digest, v_existing_sequence
  FROM public.assignment_transport_receipts AS atr
  WHERE atr.assignment_id = p_assignment_id
    AND atr.event_kind = p_event_kind
    AND atr.event_identity = p_event_identity;

  is_new := FALSE;
  conflict := (v_existing_digest IS DISTINCT FROM p_payload_digest);
  stored_aggregate_sequence := v_existing_sequence;
  RETURN NEXT;
END;
$$;

COMMENT ON TABLE public.assignment_transport_receipts IS
  'Idempotent transport receipts for Worker ACK/progress/checkpoint/result retransmission (v2 §2.4).';

COMMENT ON FUNCTION public.record_assignment_transport_receipt IS
  'Record transport event identity; replay same digest, conflict on digest mismatch.';

COMMIT;
