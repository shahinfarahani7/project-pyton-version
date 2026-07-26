# ADR-003: Keep customer credits non-transferable

## Status
Accepted

## Decision
API credits are service units, not the public token.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
