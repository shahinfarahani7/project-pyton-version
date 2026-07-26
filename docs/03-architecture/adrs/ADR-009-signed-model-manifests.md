# ADR-009: Signed model manifests

## Status
Accepted

## Decision
Every artifact has hash, signature, compatibility and rollback metadata.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
