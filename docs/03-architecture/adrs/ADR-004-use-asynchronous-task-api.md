# ADR-004: Use asynchronous task API

## Status
Accepted

## Decision
Long-running tasks return 202 and complete through polling or webhooks.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
