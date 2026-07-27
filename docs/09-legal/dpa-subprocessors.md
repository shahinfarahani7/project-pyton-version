# Data Processing Agreement and Subprocessor Schedule (GA1)

Effective version: `dpa-v2.1.0` (2026-07-20)

## Controller/processor roles
EdgeMint acts as processor for customer payloads and as controller for platform security, billing, and worker onboarding records where applicable.

## Subprocessors (GA1)
| Subprocessor | Purpose | Region | DPA status |
|---|---|---|---|
| Amazon Web Services | Compute, storage, database, secrets | EU (primary/DR) | Signed |
| Stripe | Billing, tax, identity, Connect payouts | EU/US as configured | Signed |
| Google | Play Integrity attestation | Global API | Signed |
| Apple | App Attest | Global API | Signed |

## Change control
Subprocessor additions require legal review, customer notice per contract tier, and evidence update in `evidence/actual/legal-finance/privacy-dpa.json`.

## Security measures
Encryption in transit (TLS 1.2+), encryption at rest (KMS), workspace RLS, access logging, and incident notification obligations apply to all listed subprocessors.
