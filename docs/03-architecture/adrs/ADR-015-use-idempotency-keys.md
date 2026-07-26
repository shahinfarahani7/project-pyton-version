# ADR-015: Use idempotency keys

## Status
Accepted

## Decision
Create and financial endpoints are retry-safe.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
