# Cursor Master Execution Prompt

You are implementing EdgeMint from this repository. Treat this pack as the authoritative execution contract.

## Immutable architecture

- Use Python 3.13.14 with FastAPI.
- Use PostgreSQL 18 as the only database.
- Use `psycopg 3`; do not introduce another database provider.
- Use secure WebSocket at `/events/v1` as the only real-time event transport.
- Use PostgreSQL transactional outbox, inbox, delivery, acknowledgement, replay, and dead-letter records for durable events.
- Do not introduce an external message broker, secondary database, or distributed cache.
- Use CloudEvents 1.0 JSON and the schemas under `contracts/websocket` and `contracts/asyncapi`.
- Enforce workspace isolation in authorization and PostgreSQL Row-Level Security.
- Store money only as integer micro-EUR and apply HALF_UP rounding.
- Keep the ledger append-only and balanced.
- Keep token settlement disabled for GA1.
- Implement server-side automatic assignment only. Current consent plus Worker Available status authorizes assignment; never add per-task Accept/Reject UI, API, state, event, or timeout.
- Treat WebSocket ACK as transport receipt only. The worker agent must auto-start a valid lease or machine-report canonical unavailability.

## Execution protocol

1. Run `bash tools/validate_all.sh` before changing code.
2. Read `production/canonical-decisions.yaml`, `production/AUTO-ASSIGNMENT-PROTOCOL.md`, `production/WEBSOCKET-EVENT-RELAY-ARCHITECTURE.md`, and `database/README.md`.
3. Read `cursor/CURSOR-EXECUTION-ORDER.md` and follow its dependency-aware runbook.
4. Read `cursor/VERIFICATION-PROMPTS.md` and run the matching independent verification prompt at every required checkpoint.
5. Execute `cursor/work-packages.json` in dependency order.
6. Within each work package, modify only `allowedPaths`.
7. Implement every required output and acceptance criterion.
8. Execute every verification command exactly as written.
9. Write machine-readable evidence at the declared evidence path only after all commands pass.
10. Never fabricate credentials, approvals, hashes, test output, signed artifacts, cloud plans, restore evidence, or deployment evidence.
11. Stop on any rule in `cursor/STOP-RULES.md`.
12. Do not mark production complete unless `tools/production_gate.py` passes with real evidence bound to the exact commit and artifact hashes.

## Event implementation rule

Every state-changing transaction that emits an event must insert the business changes and the outbox row in the same PostgreSQL transaction. Consumers must insert an inbox row in the same transaction as their side effects before acknowledging the WebSocket delivery. Acknowledgement before commit is forbidden.
