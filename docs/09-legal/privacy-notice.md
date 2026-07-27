# Privacy Notice (GA1)

Effective version: `privacy-notice-v2.1.0` (2026-07-20)

## Data categories
Customer payloads, results, billing records, worker device signals, consent records, and audit logs are processed according to data class policies (`public-v2`, `internal-v2`, `confidential-v2`, `restricted-v2`).

## Retention
Default customer payload retention follows data class schedules. Event store retention is 30 days; dead-letter retention is 90 days. Consent evidence is retained for 2555 days.

## Subprocessors
Primary subprocessors include AWS (infrastructure), Stripe (billing/tax/identity/payout), and attestation providers (Google Play Integrity, Apple App Attest). The DPA schedule lists current subprocessors and change notification rules.

## Rights
DSAR intake, export, and deletion workflows preserve financial and audit records required by law while removing customer payloads where permitted.

## Cross-border transfers
GA1 production data remains in EU-primary and EU-DR regions unless workspace policy and DPA authorize otherwise.
