# Service-by-Service Backlog

## Foundation
1. policy compiler/registry and validation pipeline.
2. identity, tenant scope and API credentials.
3. PostgreSQL migrations, row-level security, transactional outbox/inbox, durable WebSocket delivery, and observability baseline.

## Customer control plane
4. file ingestion and malware/type validation.
5. quote/pricing/cost engine.
6. task/revision/attempt APIs.
7. billing balance, reservation and ledger.
8. webhook delivery and SDK generation.

## Worker plane
9. challenge authentication and attestation adapter.
10. heartbeat/capability projection.
11. router, deterministic queue selection, atomic auto-lease, delivery, automatic start and fencing.
12. model registry/download/signature.
13. result upload, verification and consensus.
14. reward accrual, holds and earnings API.

## Commercial/operations
15. subscriptions, entitlement and capacity contracts.
16. invoices, payments, refunds and disputes.
17. fraud cases and operations console.
18. claim epochs and settlement adapter, disabled until gate.

Each item is complete only when API, event, migration, metrics, runbook and traceability evidence pass.
