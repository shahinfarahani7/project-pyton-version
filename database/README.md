# PostgreSQL Database Contract

PostgreSQL 18 is the only relational database for EdgeMint v5.0. The migrations in `database/sql` are the canonical schema source and are applied in lexical order by `tools/run_postgresql_migrations.sh`.

## Required capabilities

- `pgcrypto` for cryptographically strong UUID generation.
- Transaction-local tenant context through `set_config('app.workspace_id', value, true)`.
- `ENABLE` and `FORCE ROW LEVEL SECURITY` on workspace-owned tables.
- `FOR UPDATE SKIP LOCKED` for atomic queue claims, outbox claims and delivery claims.
- PL/pgSQL functions for ledger invariants, auto-assignment leasing, lease renewal, durable event delivery and acknowledgement.
- Integer `bigint` micro-EUR amounts only. Floating-point money is forbidden.
- PostgreSQL roles separate migration, runtime and read-only privileges.

Every request that touches workspace data must open a transaction and set `app.workspace_id` with `SET LOCAL` semantics before querying protected tables. Connection-pool reuse must never carry tenant context beyond the transaction.
