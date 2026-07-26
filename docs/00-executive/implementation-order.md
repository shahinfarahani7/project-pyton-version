# Authoritative Implementation Order

## Release 0 — Foundation and Contract Freeze

1. Run every validation gate and record a clean baseline.
2. Generate the repository from the canonical contracts.
3. Provision local dependencies and apply all database migrations.
4. Implement identity, workspace isolation, idempotency, outbox/inbox, observability, and audit controls.
5. Prove Task → Revision → Attempt immutability and double-entry ledger invariants.

## Release 1 — Paid Customer API

1. Launch non-transferable EUR-denominated compute credits.
2. Keep token settlement disabled.
3. Enable OCR, structured document extraction, and transcription.
4. Use edge-preferred routing with customer-controlled cloud fallback.
5. Complete the end-to-end paid-task vertical slice before adding more task types.

## Release 2 — Worker Marketplace

1. Enable dynamic scarcity pricing and reliability tiers.
2. Enable attestation, golden tasks, fraud signals, and reward holds.
3. Add dedicated enterprise pools and residency-aware routing.
4. Expand models only after signed artifacts, licenses, and device benchmarks pass.

## Release 3 — Optional Token Settlement

Token settlement is outside the first general-availability scope. It may only be enabled by a separately approved change after legal classification, KYC/AML, tax, treasury, smart-contract audit, and operational controls are signed off.
