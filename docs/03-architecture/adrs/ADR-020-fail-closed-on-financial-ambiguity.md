# ADR-020: Fail closed on financial ambiguity

## Status
Accepted

## Decision
Charges and rewards do not finalize when reconciliation is incomplete.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
