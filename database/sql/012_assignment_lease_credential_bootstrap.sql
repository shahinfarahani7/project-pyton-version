BEGIN;

CREATE TABLE IF NOT EXISTS public.assignment_lease_credentials (
  assignment_id uuid NOT NULL PRIMARY KEY,
  worker_device_id uuid NOT NULL,
  lease_token_ciphertext bytea NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_assignment_lease_credentials_assignment
    FOREIGN KEY (assignment_id) REFERENCES public.assignments(id) ON DELETE CASCADE,
  CONSTRAINT FK_assignment_lease_credentials_device
    FOREIGN KEY (worker_device_id) REFERENCES public.worker_devices(id),
  CONSTRAINT CK_assignment_lease_credentials_ciphertext
    CHECK (octet_length(lease_token_ciphertext) >= 29)
);

CREATE INDEX IF NOT EXISTS IX_assignment_lease_credentials_device
  ON public.assignment_lease_credentials(worker_device_id, assignment_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.assignment_lease_credentials TO edgemint_runtime;

COMMIT;
