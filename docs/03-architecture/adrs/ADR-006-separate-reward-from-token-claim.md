# ADR-006: Separate reward from token claim

## Status
Accepted

## Decision
Reward accrual is off-chain; claims are batched after verification.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
