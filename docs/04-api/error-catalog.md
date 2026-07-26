# Stable Error Catalog

| Code | HTTP | Retryable | Financial side effect |
|---|---:|---|---|
| AUTH_INVALID_CREDENTIAL | 401 | no | none |
| AUTH_SCOPE_REQUIRED | 403 | no | none |
| TENANT_RESOURCE_NOT_FOUND | 404 | no | none |
| IDEMPOTENCY_CONFLICT | 409 | no | original operation unchanged |
| VERSION_CONFLICT | 412 | refresh resource | none |
| INPUT_SCHEMA_INVALID | 422 | after edit | none |
| FILE_NOT_READY | 409 | yes | none |
| QUOTE_EXPIRED | 409 | requote | release old reservation if any |
| INSUFFICIENT_CREDIT | 402 | after funding | none |
| TASK_INVALID_TRANSITION | 409 | no | none |
| TASK_REVISION_IMMUTABLE | 409 | create revision | none |
| ASSIGNMENT_START_WINDOW_EXPIRED | 409 | refresh the current auto-assigned lease | none |
| ASSIGNMENT_STALE_FENCE | 409 | no | result not payable |
| WORKER_POLICY_NOT_SATISFIED | 403 | after remediation | none |
| RESOURCE_MEMORY_PRESSURE | 409 | route/retry | according to failure matrix |
| VERIFICATION_DISAGREEMENT | 409 | escalation | holds remain |
| LEDGER_INVARIANT_FAILED | 500 | operator only | financial finalization paused |
| TOKEN_CLAIM_NOT_ENABLED | 403 | after gate | none |
| CLAIM_COMPLIANCE_HOLD | 409 | review | reward remains reserved/held |
| PROVIDER_RESULT_AMBIGUOUS | 503 | reconciliation | no duplicate provider command |
