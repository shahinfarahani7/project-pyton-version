# Production Gates v2

## G0 — Contract integrity
- `bash tools/validate_all.sh` passes.
- no production manifest contains placeholder digest, unresolved reference or float money.

## G1 — Product integrity
- critical use cases pass end-to-end in staging.
- task edit creates a revision and never mutates prior evidence.
- worker disconnect/restart tests recover or safely requeue.

## G2 — Financial integrity
- quote replay is deterministic.
- reservation = charge + release for every terminal task.
- ledger is balanced by transaction and currency.
- payout/claim batches reconcile to provider or chain evidence.

## G3 — Security/privacy
- tenant isolation, API-key rotation, attestation, payload encryption, secure deletion and webhook replay tests pass.
- threat model and DPIA decisions are signed.

## G4 — Reliability
- SLO load, soak, chaos, backup restore and region-failover tests pass.
- rollback is tested for application, policy and model rollout.

## G5 — Token claim
- legal, KYC/AML, tax, treasury, contract audit and store-disclosure gates are approved.
- until G5 passes, token claim endpoints return `TOKEN_CLAIM_NOT_ENABLED`.
