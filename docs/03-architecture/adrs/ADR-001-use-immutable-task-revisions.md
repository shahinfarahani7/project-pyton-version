# ADR-001: Use immutable task revisions

## Status
Accepted

## Decision
Submitted Task revisions never change; edits create a new revision.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
