BEGIN;

ALTER TABLE public.worker_preferences
  ADD COLUMN IF NOT EXISTS contribution_mode_id varchar(32) NOT NULL DEFAULT 'balanced'
    CONSTRAINT CK_worker_preferences_contribution_mode
    CHECK (contribution_mode_id IN ('balanced', 'performance'));

COMMIT;
