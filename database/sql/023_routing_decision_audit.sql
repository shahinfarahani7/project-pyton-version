BEGIN;

CREATE TABLE IF NOT EXISTS public.routing_decision_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_attempt_id uuid NOT NULL,
  task_id varchar(128) NOT NULL,
  router_epoch bigint NOT NULL CONSTRAINT CK_routing_decision_audit_epoch CHECK(router_epoch >= 0),
  policy_hash varchar(64) NOT NULL,
  winner_worker_id varchar(128) NULL,
  winner_score bigint NOT NULL CONSTRAINT CK_routing_decision_audit_score CHECK(winner_score >= 0),
  candidates_json jsonb NOT NULL,
  decision_trace_json jsonb NOT NULL,
  decided_at_utc timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT FK_routing_decision_audit_attempt
    FOREIGN KEY(task_attempt_id) REFERENCES public.task_attempts(id)
);

CREATE INDEX IF NOT EXISTS ix_routing_decision_audit_attempt
  ON public.routing_decision_audit(task_attempt_id, decided_at_utc DESC);

COMMIT;
