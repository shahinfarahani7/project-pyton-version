# ADR-014: Use HMAC webhook signatures

## Status
Accepted

## Decision
Webhook deliveries are signed and replay-protected.

## Consequences
- Implementation must expose the decision through contracts and automated tests.
- Any exception requires a documented policy override and audit entry.
