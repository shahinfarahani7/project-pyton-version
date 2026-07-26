# ADR-002: Use double-entry ledger

## Status
Accepted

## Decision
All financial balances derive from append-only journal entries.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
