# Idempotency and Concurrency

- Idempotency scope is `(workspace_id, operation_id, idempotency_key)`.
- request hash excludes transport headers but includes canonical body and path identity.
- same key/same hash returns stored response; same key/different hash returns `IDEMPOTENCY_CONFLICT`.
- records are written before external side effects and retained for at least the longest client retry window.
- task revision number, attempt number, lease fencing token and claim batch sequence are allocated under database locks.
- external callbacks use an inbox table keyed by provider and message ID.
- outbox publication is at-least-once; consumers must be idempotent.
