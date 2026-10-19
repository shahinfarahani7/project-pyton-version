-- Verified uptime participation levels and uptime Booster (worker-scoped, not EUR).

BEGIN;

CREATE TABLE IF NOT EXISTS public.worker_uptime_ledgers (
  worker_id uuid NOT NULL PRIMARY KEY,
  policy_version varchar(128) NOT NULL,
  actual_uptime_ms bigint NOT NULL DEFAULT 0
    CONSTRAINT CK_uptime_actual_nonneg CHECK (actual_uptime_ms >= 0),
  booster_bonus_ms bigint NOT NULL DEFAULT 0
    CONSTRAINT CK_uptime_bonus_nonneg CHECK (booster_bonus_ms >= 0),
  recomputed_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_uptime_ledger_worker FOREIGN KEY (worker_id) REFERENCES public.workers(id)
);

CREATE TABLE IF NOT EXISTS public.worker_uptime_device_cursors (
  worker_device_id uuid NOT NULL PRIMARY KEY,
  worker_id uuid NOT NULL,
  last_sequence_number integer NOT NULL DEFAULT 0
    CONSTRAINT CK_uptime_cursor_seq CHECK (last_sequence_number >= 0),
  CONSTRAINT FK_uptime_cursor_device FOREIGN KEY (worker_device_id) REFERENCES public.worker_devices(id),
  CONSTRAINT FK_uptime_cursor_worker FOREIGN KEY (worker_id) REFERENCES public.workers(id)
);

CREATE TABLE IF NOT EXISTS public.worker_uptime_segments (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_id uuid NOT NULL,
  worker_device_id uuid NOT NULL,
  to_sequence_number integer NOT NULL,
  interval_start_utc timestamptz NOT NULL,
  interval_end_utc timestamptz NOT NULL,
  actual_ms bigint NOT NULL CONSTRAINT CK_uptime_segment_actual CHECK (actual_ms >= 0),
  bonus_ms bigint NOT NULL CONSTRAINT CK_uptime_segment_bonus CHECK (bonus_ms >= 0),
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_uptime_segment_worker FOREIGN KEY (worker_id) REFERENCES public.workers(id),
  CONSTRAINT FK_uptime_segment_device FOREIGN KEY (worker_device_id) REFERENCES public.worker_devices(id),
  CONSTRAINT CK_uptime_segment_window CHECK (interval_end_utc > interval_start_utc),
  CONSTRAINT UQ_uptime_segment_device_seq UNIQUE (worker_device_id, to_sequence_number)
);

CREATE INDEX IF NOT EXISTS ix_uptime_segments_worker
  ON public.worker_uptime_segments (worker_id, interval_start_utc);

CREATE TABLE IF NOT EXISTS public.worker_uptime_boosts (
  id uuid NOT NULL DEFAULT uuidv7() PRIMARY KEY,
  worker_id uuid NOT NULL,
  idempotency_key varchar(128) NOT NULL,
  token_debit_receipt_id varchar(128) NOT NULL,
  grant_ms bigint NOT NULL CONSTRAINT CK_uptime_boost_grant CHECK (grant_ms > 0),
  purchased_at_utc timestamptz NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_uptime_boost_worker FOREIGN KEY (worker_id) REFERENCES public.workers(id),
  CONSTRAINT UQ_uptime_boost_idempotency UNIQUE (worker_id, idempotency_key),
  CONSTRAINT UQ_uptime_boost_debit UNIQUE (token_debit_receipt_id)
);

CREATE INDEX IF NOT EXISTS ix_uptime_boost_worker_purchased
  ON public.worker_uptime_boosts (worker_id, purchased_at_utc DESC);

COMMIT;
