BEGIN;

ALTER TABLE public.model_versions
  ADD COLUMN IF NOT EXISTS public_id varchar(32) NULL,
  ADD COLUMN IF NOT EXISTS rollback_version_id uuid NULL,
  ADD COLUMN IF NOT EXISTS runtime_abi varchar(64) NOT NULL DEFAULT 'onnxruntime-1.18',
  ADD COLUMN IF NOT EXISTS minimum_device_tier varchar(8) NOT NULL DEFAULT 'T1',
  ADD COLUMN IF NOT EXISTS peak_ram_bytes bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS minimum_free_storage_bytes bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS manifest_json jsonb NULL,
  ADD COLUMN IF NOT EXISTS signature_sha256 char(64) NULL,
  ADD COLUMN IF NOT EXISTS license_status varchar(32) NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS benchmark_evidence_path varchar(512) NULL,
  ADD COLUMN IF NOT EXISTS row_version bigint NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP;

CREATE UNIQUE INDEX IF NOT EXISTS UQ_model_versions_public_id
  ON public.model_versions (public_id)
  WHERE public_id IS NOT NULL;

ALTER TABLE public.model_versions
  ADD CONSTRAINT FK_model_versions_rollback
  FOREIGN KEY (rollback_version_id) REFERENCES public.model_versions(id);

ALTER TABLE public.model_rollouts
  ADD COLUMN IF NOT EXISTS public_id varchar(32) NULL,
  ADD COLUMN IF NOT EXISTS rollback_version_id uuid NULL;

CREATE UNIQUE INDEX IF NOT EXISTS UQ_model_rollouts_public_id
  ON public.model_rollouts (public_id)
  WHERE public_id IS NOT NULL;

ALTER TABLE public.model_downloads
  ADD COLUMN IF NOT EXISTS resume_token_hash bytea NULL,
  ADD COLUMN IF NOT EXISTS last_chunk_index int NOT NULL DEFAULT -1,
  ADD COLUMN IF NOT EXISTS chunk_digests_json jsonb NOT NULL DEFAULT '[]'::jsonb;

COMMIT;
