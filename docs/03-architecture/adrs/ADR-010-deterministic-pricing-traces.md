# ADR-010: Deterministic pricing traces

## Status
Accepted

## Decision
Every quote records rule versions and calculation steps.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
