# EdgeMint Production Execution Pack v5.0

This English-only execution pack is the canonical source for implementing EdgeMint with Cursor.

## Fixed architecture

- PostgreSQL 18 is the only database.
- Secure WebSocket is the only real-time event transport.
- PostgreSQL transactional outbox, inbox, delivery, acknowledgement, replay, and dead-letter records provide durability.
- Amazon RDS for PostgreSQL Multi-AZ is the production database service.
- Amazon EKS runs the Python services, portals, and Event Relay.
- No external message broker, secondary database, or distributed cache is permitted in the canonical GA1 architecture.

Start with `START-HERE.md`, then execute `cursor/CURSOR-MASTER-PROMPT.md`.
