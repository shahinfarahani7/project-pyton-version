# Architecture Decision Register

| ID | Decision | Status |
|---|---|---|
| ADR-001 | The GA1 backend uses Python 3.13.14 with FastAPI and contract-first services. | Accepted |
| ADR-002 | PostgreSQL 18 is the only database and persistence authority. | Accepted |
| ADR-003 | Amazon RDS for PostgreSQL Multi-AZ is the production database service. | Accepted |
| ADR-004 | Secure WebSocket at `/events/v1` is the only real-time event transport. | Accepted |
| ADR-005 | PostgreSQL transactional outbox, inbox, delivery, acknowledgement, replay, and dead-letter tables provide durable event semantics. | Accepted |
| ADR-006 | Event delivery is at least once with event-ID idempotency and per-aggregate ordering. | Accepted |
| ADR-007 | Workspace isolation is enforced in APIs and PostgreSQL Row-Level Security through read-only session context. | Accepted |
| ADR-008 | Monetary values are integer micro-EUR and rounding is HALF_UP. | Accepted |
| ADR-009 | The ledger is immutable, double-entry, EUR-only for GA1, and posted through one stored procedure. | Accepted |
| ADR-010 | Worker rewards are fiat liabilities paid through regulated payout rails; token settlement is disabled for GA1. | Accepted |
| ADR-011 | AWS, EKS, Terraform, Helm, Amazon S3, Cognito, WAF, KMS, and signed immutable container images are canonical. | Accepted |
| ADR-012 | No external message broker, secondary database, or distributed cache is permitted without a future approved architecture change. | Accepted |
| ADR-013 | Production certification is fail-closed and requires genuine signed environment evidence. | Accepted |
