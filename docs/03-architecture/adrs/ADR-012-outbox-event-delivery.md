# ADR-012: Outbox event delivery

## Status
Accepted

## Decision
Database transaction and event publication use an outbox.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
