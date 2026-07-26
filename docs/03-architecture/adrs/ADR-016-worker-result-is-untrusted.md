# ADR-016: Worker result is untrusted

## Status
Accepted

## Decision
All results pass verification before finalization.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
