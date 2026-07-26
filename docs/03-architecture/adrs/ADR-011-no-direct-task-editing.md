# ADR-011: No direct task editing

## Status
Accepted

## Decision
Retry creates Attempt; modification creates Revision.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
