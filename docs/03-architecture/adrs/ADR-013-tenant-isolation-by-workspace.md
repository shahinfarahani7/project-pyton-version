# ADR-013: Tenant isolation by workspace

## Status
Accepted

## Decision
All tenant-bound data carries organization and workspace identifiers.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
