# EdgeMint v5.0 Python/PostgreSQL Migration Report

## Scope

This revision changes the canonical backend and relational database stack while preserving EdgeMint's product behavior, automatic-assignment protocol, WebSocket-only realtime transport, evidence model and Work Package execution discipline.

## Previous baseline

- Backend: C#/.NET service projects.
- Database: Microsoft SQL Server migrations and runtime assumptions.
- Production database service: Amazon RDS for SQL Server.

## New canonical baseline

- Runtime: Python 3.13.14.
- API framework: FastAPI 0.140.0 with Pydantic 2.13.4 and Uvicorn 0.51.0.
- Persistence: SQLAlchemy 2.0.51 and psycopg 3.3.4.
- Migration/tooling: Alembic 1.18.5 plus the repository's checksum-enforced ordered SQL migration runner.
- Database: PostgreSQL 18.4 on Amazon RDS for PostgreSQL Multi-AZ.
- Tests and quality: pytest, pytest-asyncio, Ruff and mypy.

## Code migration

- Removed all `.cs`, `.csproj`, `.sln`, `.fs` and `.fsproj` source artifacts.
- Replaced the backend solution with a Python package under `src/backend`.
- Added one FastAPI entrypoint and digest-pinned Dockerfile contract for each of the 21 services.
- Ported shared settings, transaction ownership, workspace context, public IDs and service lifecycle primitives to Python.
- Ported the durable WebSocket Event Relay to FastAPI/SQLAlchemy with PostgreSQL-backed connection, subscription, delivery, ACK and reconnect state.
- Ported the executable reference engines and tests to `reference/python`.
- Converted Work Package and Execution Unit commands from .NET commands to Python/pytest commands.

## Database migration

- Replaced SQL Server migration scripts with nine ordered PostgreSQL migration units.
- Converted identifiers to PostgreSQL UUID/UUIDv7-compatible columns.
- Converted JSON payloads to `jsonb` and timestamps to `timestamptz`.
- Replaced SQL Server locking hints with transactional `FOR UPDATE SKIP LOCKED` claims.
- Replaced session context with transaction-local `set_config('app.workspace_id', ..., true)`.
- Implemented `ENABLE ROW LEVEL SECURITY` and `FORCE ROW LEVEL SECURITY` on workspace-owned data.
- Implemented PL/pgSQL functions for queue claim, automatic assignment, fencing, lease start/renewal, outbox claim, WebSocket delivery and acknowledgement.
- Preserved integer `bigint` micro-EUR and append-only balanced-ledger invariants.
- Added runtime, migration-owner and read-only privilege boundaries, including a controlled BYPASSRLS system owner for cross-workspace routing functions.

## Infrastructure and delivery migration

- Replaced RDS SQL Server resources with Amazon RDS for PostgreSQL 18.4 controls.
- Updated port, parameter-group family, IAM database authentication, encryption, Multi-AZ, backup and deletion-protection contracts.
- Replaced backend container build commands and release inputs with Python runtime inputs.
- Updated Compose to PostgreSQL and checksum-enforced migration initialization.
- Updated CI/CD, SBOM, provenance, release evidence and Cursor verification prompts for Python/PostgreSQL.

## Verification completed in this revision

- Python compile check completed.
- Included backend suite: 27 tests passed.
- 608 DSL documents compiled.
- 141 OpenAPI operations matched 141 operation contracts and 141 execution units.
- 186 event contracts and examples validated.
- 595,000 semantic vectors passed.
- Nine PostgreSQL migrations, 74 domain tables and 36 RLS policies passed repository validation.
- Package manifest and SHA-256 inventory passed after regeneration.
- No active .NET project/source artifact or SQL Server runtime dependency remains.

## Verification still requiring the target environment

This repository-level migration does not claim that a live environment has been certified. The following remain mandatory:

- Apply clean-install and upgrade migrations to PostgreSQL 18.4 using the migration-owner role.
- Run concurrency, deadlock, RLS-isolation, failover and recovery tests against real PostgreSQL.
- Build every Python image using the approved digest-pinned Python 3.13.14 base image.
- Run Terraform parsing/plan under the locked validator environment and target AWS accounts.
- Complete all Work Packages and external evidence required by `production/EXTERNAL-EVIDENCE-CONTRACT.md`.
- Pass `python tools/production_gate.py` using signed, real evidence.

## Verdict

The package's canonical architecture, code scaffold, database schema, contracts, Cursor plan and verification system have been migrated to Python/PostgreSQL. The package is ready for controlled implementation from WP-000; it is not yet a production-certified deployed system.
