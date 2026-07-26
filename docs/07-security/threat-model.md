# Threat Model Summary

## Assets
customer payloads/results, tenant credentials, worker keys, model artifacts, policy activation, credit balance, ledger, reward balance, token claims and audit evidence.

## Primary threats and controls
- cross-tenant access: RLS, workspace claims, negative tests.
- stolen API key: hashing, scopes, expiration, rotation, IP policy and anomaly detection.
- malicious worker result: attestation signals, signed lease/result, verification, golden tasks and consensus anti-affinity.
- replay/double payout: nonce, idempotency, fencing token, inbox and unique attempt accrual.
- model tampering: signed manifest, hash, secure install and revocation.
- payload extraction: envelope encryption, short-lived URLs, temporary secure deletion and no Dart-heap retention.
- operator abuse: least privilege, elevation, dual approval and immutable audit.
- pricing/policy tampering: signed immutable policy activation and deterministic quote replay.
- claim fraud: KYC/jurisdiction gate, address verification, hold, batch limits and reconciliation.
