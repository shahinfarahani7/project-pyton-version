# Production Handover

GA1 production release evidence is bound to an immutable commit SHA and signed manifest under `evidence/actual/release-evidence.json`.

## On-call ownership
- **SRE:** progressive canary promotion, rollback, DR runbooks (`docs/08-sre/`)
- **Security:** incident response, break-glass audit (`docs/07-security/`)
- **Finance:** payout reconciliation, Stripe provider drift (`src/backend/edgemint/payments/`)
- **Legal/Privacy:** DSAR intake, subprocessor changes (`docs/09-legal/`)

## Release verification
```bash
python tools/verify_canary_evidence.py evidence/actual/canary
python tools/production_gate.py --evidence-dir evidence/actual --expected-commit-sha "<commit>" \
  --manifest-signature evidence/actual/release-evidence.sig \
  --trusted-key evidence/actual/trusted-release-key.pem \
  --expected-trusted-key-sha256 "<sha256>"
```

## Canary stages
internal → 1% → 5% → 25% → 100% with soak windows defined in `deploy/gitops/promotion/canary-stages.yaml`. Automatic rollback triggers on SLO burn, canary error rate breach, or migration incompatibility.

## Operations constraints
- Token settlement and public token sale remain disabled for GA1.
- Unsupported worker countries fail closed for earning and payout.
- Release promotion requires all seven function approvals on the exact immutable release artifact set.
