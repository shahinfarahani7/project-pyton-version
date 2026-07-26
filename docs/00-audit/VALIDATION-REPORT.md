# EdgeMint Validation Report

This report is regenerated for the audited v2.1 package.

## Required command

```bash
bash tools/validate_all.sh
```

## Enforced checks

1. Strict JSON Schema and semantic DSL validation.
2. OpenAPI 3.1, AsyncAPI 3.0, CloudEvent and permission consistency.
3. Exact requirement, operation, use-case, scenario, event, error and SQL traceability.
4. Independent semantic recomputation of 595,000 vectors.
5. PostgreSQL migration, state-constraint, row-level-security, immutable revision, fencing, ledger, and durable WebSocket eventing checks.
6. Kubernetes structure and explicit image-digest blocker detection.
7. Reference-code parity and absence of implementation placeholders.
8. One sample per OpenAPI operation and journey operation validation.
9. External production blocker enumeration.
10. Documentation path/link validation and deterministic DSL compilation.

## Expected audited counts

| Surface | Count |
|---|---:|
| DSL documents | 608 |
| DSL kinds | 38 |
| OpenAPI operations | 141 |
| OperationContract documents | 141 |
| Canonical events | 186 |
| Business UseCases | 60 |
| Business scenarios | 120 |
| All scenarios | 215 |
| Required SQL tables | 59 |
| Semantic vector lines | 595,000 |
| Operation samples | 141 |
| Kubernetes deployments/services/service accounts | 19 / 19 / 19 |
| Explicit external release blockers | 36 |

A release blocker is not a validation failure when it is declared and fail-closed. It becomes a production activation failure if the corresponding gated component is enabled without evidence.
