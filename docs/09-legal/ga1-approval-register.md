# GA1 Legal and Finance Approval Register

Machine-readable evidence lives under `evidence/actual/legal-finance/`. This register summarizes human-readable scope for GA1 production readiness.

## Approved dimensions
- **Countries:** DE, FR, NL, BE, AT, IE, ES, IT, PT, FI (payout allowlist; unsupported countries fail closed)
- **Task types:** All rules in `public-eur-2026q3-v2`
- **Data classes:** public, internal, confidential, restricted
- **Models:** paddleocr-mobile, gemma-3n-e2b-int4, whisper-base-int8
- **Payment flows:** billing, tax, KYC, payout, ledger reconciliation
- **Token claims:** disabled for GA1 (`canonical-decisions.yaml`)

## Signed approvals
Legal, privacy, finance/tax/payout, and model license approvals are stored with version pins and expiry dates in `signed-approvals.json`.

## Product surface guardrails
No guaranteed earnings, hidden computation, token value promises, or unsupported geography marketing.
