# EdgeMint Production Execution Pack v5.0

This English-only execution pack is the canonical source for implementing EdgeMint with Cursor. Version 5.0 preserves the automatic-assignment contract introduced in v4.1: no per-task accept/reject interaction exists.

## Fixed architecture

- PostgreSQL 18 is the only database.
- Secure WebSocket is the only real-time event transport.
- PostgreSQL transactional outbox, inbox, delivery, acknowledgement, replay, and dead-letter records provide durability.
- Amazon RDS for PostgreSQL Multi-AZ is the production database service.
- Amazon EKS runs the Python services, portals, and Event Relay.
- No external message broker, secondary database, or distributed cache is permitted in the canonical GA1 architecture.

Start with `START-HERE.md`, then execute `cursor/CURSOR-MASTER-PROMPT.md`.

## Fixed assignment protocol

- A current consent record plus Worker `Available` status is the opt-in authority.
- The router atomically reserves capacity, creates the lease and fence token, and targets the assignment to one worker.
- The worker agent starts automatically after validating the signed assignment.
- WebSocket acknowledgement proves message receipt only; it is not execution consent.
- If local conditions changed, the agent reports a machine-detected unavailability reason and the server reassigns with a higher fence token.
- No per-task Accept or Reject button, API, state, event, or timeout is permitted.
