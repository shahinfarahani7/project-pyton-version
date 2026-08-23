# Automatic Lease Credential Bootstrap — 2026-08-22

## Outcome

The PostgreSQL Assignment can now provide its raw `leaseToken` to the targeted Worker without a per-task Accept/Reject step and without persisting the raw capability in Outbox/WebSocket payloads.

## Implemented flow

1. Router generates the raw lease capability and its SHA-256 hash.
2. Router encrypts the raw capability with AES-256-GCM, binding the ciphertext to `worker_device_id` as associated data.
3. `acquire_assignment_lease` creates the Assignment and transactional Outbox event using only the hash and non-secret assignment metadata.
4. In the same database transaction, Router inserts the ciphertext into `assignment_lease_credentials`. Failure rolls back the Assignment and Outbox write.
5. The WebSocket `assignment.leased` event is a wake-up signal only.
6. The Worker automatically calls `GET /assignments:next` with its Worker session.
7. Worker Registry resolves the session, enforces active device and current attestation, locks the existing targeted lease, decrypts the credential, verifies it against `lease_token_hash`, and returns the full automatic Assignment with `Cache-Control: no-store`.
8. Replayed notifications return the same credential while the Assignment remains `leased`; no token rotation race is introduced.
9. Once the Assignment becomes `running`, replayed lease notifications no longer bootstrap it again.

## Security properties

- No raw `leaseToken` is stored in `outbox_events`, WebSocket delivery tables, logs, or URLs.
- Ciphertext is bound to the selected Worker device and cannot be decrypted for another device ID.
- Production and staging require `EDGEMINT_LEASE_CREDENTIAL_ENCRYPTION_KEY`, containing URL-safe base64 for exactly 32 random bytes.
- Credential responses are non-cacheable.
- Hash/ciphertext mismatch fails closed with `LEASE_CREDENTIAL_UNAVAILABLE`.
- No Accept, Reject, offer, or per-task consent API was added.

## Files changed

- `src/backend/edgemint/security/lease_credentials.py`
- `src/backend/edgemint/routing/service.py`
- `src/backend/edgemint/workers/assignments.py`
- `src/backend/edgemint/services/worker_registry.py`
- `src/backend/edgemint/building_blocks/settings.py`
- `src/backend/edgemint/workers/errors.py`
- `database/sql/012_assignment_lease_credential_bootstrap.sql`
- `src/backend/tests/workers/test_assignment_credential_bootstrap.py`
- `src/backend/tests/routing/test_lease_credential_persistence.py`
- `tools/validate_sql.py`

## Verification evidence

- Full Python source and test compile: passed.
- PostgreSQL contract validator: passed; 13 migration files, 75 required tables, 36 RLS tables, zero errors.
- AES-256-GCM runtime smoke: passed, including wrong-device authentication failure.
- Bootstrap source contract: passed for encrypted persistence, targeted lookup, existing-lease-only behavior, stable replay, no raw token in Outbox, and no Accept/Reject.
- The focused pytest suite was added but could not be executed in this workspace because `pytest`, FastAPI, and SQLAlchemy are not installed. This is reported as an environment limitation, not a passing runtime test.

## Next production checkpoint

Run migration 012 against PostgreSQL, configure the dedicated encryption key on Router and Worker Registry, then execute the Production Auto-Assignment E2E. The E2E must prove Assignment + credential + Outbox atomicity, targeted WebSocket delivery, automatic bootstrap, start, renew, result, and no credential leakage.
