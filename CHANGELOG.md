# Changelog

## 5.0.0 - 2026-07-26

- Replaced the C#/.NET backend baseline with Python 3.13.14 and FastAPI.
- Replaced Microsoft SQL Server with PostgreSQL 18.4 on Amazon RDS for PostgreSQL.
- Ported the backend service scaffold, Event Relay, shared building blocks, reference engines and tests to Python.
- Rebuilt the database as nine ordered PostgreSQL migrations using UUID/UUIDv7, `jsonb`, `timestamptz`, PL/pgSQL, transaction-local workspace context, `FOR UPDATE SKIP LOCKED` and `FORCE ROW LEVEL SECURITY`.
- Migrated Docker, Compose, Terraform, Helm, CI/CD, release inputs, SBOM/provenance controls, Cursor Work Packages and verification prompts to Python/PostgreSQL.
- Preserved the v4.1 automatic-assignment contract: global availability opt-in, no per-task Accept/Reject, atomic lease creation, monotonic fence tokens and transport-only WebSocket ACK.
- Added `STACK-MIGRATION-PYTHON-POSTGRESQL.md` and refreshed all package integrity metadata.

## 4.1.0 - 2026-07-21

- Added the authoritative Cursor execution-order runbook and independent verification prompt suite.
- Replaced per-task Worker Offer/Accept/Reject with atomic server-side automatic leases.
- Added explicit Available/Unavailable opt-in, deterministic queue fairness and feature normalization.
- Added automatic start, machine-detected unavailability, renewal sequencing and start-timeout requeue.

## 4.0.0 - 2026-07-21

- Replaced the earlier broker-based event design with a durable secure WebSocket Event Relay.
- Standardized the v4 runtime baseline on Microsoft SQL Server with SQL-backed outbox, inbox, delivery, acknowledgement, replay and dead-letter records.
- Added WebSocket protocol schemas, reliability rules, security rules, implementation Work Packages and validators.
