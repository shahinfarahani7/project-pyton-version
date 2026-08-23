# Production Auto-Assignment E2E — 2026-08-22

## Implementation outcome

The production Worker Registry now exposes real `started` and `renew` commands instead of registering those routes only in development mode.

Implemented path:

`Router lease → encrypted credential row → assignment.leased Outbox → Worker bootstrap → start_auto_assigned_work → assignment.started Outbox → renew_auto_assignment_lease → assignment.lease_renewed Outbox`

No Worker Accept/Reject operation exists in this path.

## Production defect found and fixed

Worker enrollment persisted `attestation_status='verified'`, while PostgreSQL lease acquisition and credential bootstrap required `valid`. A normally enrolled production Worker was therefore permanently ineligible. The lease gate and bootstrap now use the canonical existing value `verified`, consistent with enrollment, readiness checks and the existing tests.

## Added production behavior

- `POST /assignments/{assignmentId}:started`
  - Worker session and target device binding.
  - Raw token hash and fence validation.
  - Latest persisted heartbeat required.
  - PostgreSQL `start_auto_assigned_work` transition.
  - Idempotent replay when the same lease is already running.
  - Transactional `assignment.started` Outbox event.
- `POST /assignments/{assignmentId}:renew`
  - Worker session and target device binding.
  - Raw token hash and fence validation.
  - PostgreSQL monotonic renewal sequence.
  - Transactional `assignment.lease_renewed` Outbox event.
- Flutter Worker API client now includes `renewAssignment`.

## Genuine PostgreSQL E2E runner

`tools/run_production_auto_assignment_e2e.py` creates an isolated organization, workspace, Worker, verified device, consent, availability preference, heartbeat, Worker session, task revision and matching attempt inside one transaction. It then executes the production services, verifies three Assignment lifecycle Outbox events and rolls the transaction back.

Required runtime configuration:

```bash
export EDGEMINT_DATABASE_URL='postgresql+psycopg://...'
export EDGEMINT_LEASE_CREDENTIAL_ENCRYPTION_KEY='...'
python3 tools/run_production_auto_assignment_e2e.py
```

## Evidence in this workspace

- Production auto-assignment source contract: passed, 11/11 checks.
- PostgreSQL schema validator: passed, 13 migration files, 75 required tables, zero errors.
- Full Python compile: passed.
- Focused command tests were added for active credential, wrong token, expired token and stale fence.
- Genuine PostgreSQL E2E execution: blocked because this workspace has no SQLAlchemy, psycopg, database URL or PostgreSQL server. The runner returned explicit `blocked` evidence and did not claim a simulated production pass.

## Remaining boundary

The current stage proves implementation readiness through `start` and `renew`. A live PostgreSQL PASS still requires running the supplied E2E runner in the project stack. WebSocket delivery expansion/replay is the next stage. Result completion remains part of the later Production API alignment because the mobile completion body and the current OpenAPI upload-intent contract are not yet the same operation.
