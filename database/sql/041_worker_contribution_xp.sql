-- Worker contribution XP, participation level inputs, and XP boosts.
-- XP is not money: no micro-EUR column, no link to reward_entitlements.amount_micro_eur,
-- and no effect on routing, trust score, or task execution.

BEGIN;

CREATE TABLE IF NOT EXISTS public.worker_contribution_boosts (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_device_id uuid NOT NULL,
  idempotency_key varchar(128) NOT NULL,
  token_debit_receipt_id varchar(128) NOT NULL,
  bonus_bps integer NOT NULL CONSTRAINT CK_contribution_boost_bonus CHECK (bonus_bps >= 0),
  activated_at_utc timestamptz NOT NULL,
  expires_at_utc timestamptz NOT NULL,
  task_quota integer NOT NULL CONSTRAINT CK_contribution_boost_quota CHECK (task_quota > 0),
  tasks_used integer NOT NULL DEFAULT 0,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_contribution_boost_device FOREIGN KEY (worker_device_id) REFERENCES public.worker_devices(id),
  CONSTRAINT CK_contribution_boost_window CHECK (expires_at_utc > activated_at_utc),
  CONSTRAINT CK_contribution_boost_usage CHECK (tasks_used >= 0 AND tasks_used <= task_quota),
  CONSTRAINT UQ_contribution_boost_idempotency UNIQUE (worker_device_id, idempotency_key),
  CONSTRAINT UQ_contribution_boost_debit UNIQUE (token_debit_receipt_id)
);

CREATE TABLE IF NOT EXISTS public.worker_contribution_xp_awards (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  task_run_id uuid NOT NULL,
  result_candidate_id uuid NOT NULL,
  worker_device_id uuid NOT NULL,
  task_type varchar(128) NOT NULL,
  centi_xp bigint NOT NULL CONSTRAINT CK_contribution_xp_nonnegative CHECK (centi_xp >= 0),
  accepted_processing_ms bigint NULL CONSTRAINT CK_contribution_xp_processing CHECK (accepted_processing_ms IS NULL OR accepted_processing_ms >= 0),
  time_component varchar(64) NOT NULL
    CONSTRAINT CK_contribution_xp_time_component
    CHECK (time_component IN ('TIME_COMPONENT_AVAILABLE', 'TIME_COMPONENT_UNAVAILABLE')),
  boost_id uuid NULL,
  policy_version varchar(128) NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_contribution_xp_candidate FOREIGN KEY (result_candidate_id) REFERENCES public.result_candidates(id),
  CONSTRAINT FK_contribution_xp_device FOREIGN KEY (worker_device_id) REFERENCES public.worker_devices(id),
  CONSTRAINT FK_contribution_xp_boost FOREIGN KEY (boost_id) REFERENCES public.worker_contribution_boosts(id),
  CONSTRAINT CK_contribution_xp_time_pair CHECK (
    (time_component = 'TIME_COMPONENT_AVAILABLE') = (accepted_processing_ms IS NOT NULL)
  ),
  CONSTRAINT UQ_contribution_xp_task_run UNIQUE (task_run_id)
);

CREATE INDEX IF NOT EXISTS ix_contribution_xp_device
  ON public.worker_contribution_xp_awards (worker_device_id);

CREATE INDEX IF NOT EXISTS ix_contribution_boost_device
  ON public.worker_contribution_boosts (worker_device_id, expires_at_utc);

COMMIT;
