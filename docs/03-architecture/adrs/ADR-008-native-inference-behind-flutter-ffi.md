# ADR-008: Native inference behind Flutter FFI

## Status
Accepted

## Decision
Flutter orchestrates UX; model runtimes remain native.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
