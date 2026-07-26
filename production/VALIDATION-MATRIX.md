# Validation Matrix

## Executed successfully while producing v5.0

| Area | Result |
|---|---|
| English-only text scan | Passed; zero Arabic/Persian-script files |
| DSL validation | 608 documents, 38 kinds, zero errors |
| OpenAPI contracts | 141 unique operations, strict requests/responses, zero contract errors |
| Event contracts | 186 canonical events, 186 typed AsyncAPI messages, 186 unique CloudEvent examples |
| Traceability | 80 requirements, 60 use cases, 215 scenarios, 141 operation contracts, 74 discovered SQL tables |
| Semantic vectors | 595,000 vectors across pricing, reward, routing, ledger, claim, fraud, lifecycle, webhook, and resume |
| SQL static validation | 9 ordered PostgreSQL migrations, 74 required domain/platform tables, workspace RLS, fencing, ledger, outbox/inbox, replay, and retention invariants |
| Terraform source syntax | 12 HCL files parsed successfully with `python-hcl2` |
| Helm source controls | 21 services, fail-closed digest/IRSA values, security and availability controls present |
| Web applications | Dependency audit: zero known vulnerabilities; TypeScript lint, two Vitest suites, and two Vite production builds passed |
| Cursor DAG | 27 work packages, known dependencies, explicit path/output/evidence/stop rules |
| v2.1 audit closure | 147 of 147 findings mapped to English canonical evidence and execution work packages |

## Mandatory evidence not fabricated by this package

The following validation must be produced by Cursor and the target organization during execution: Python 3.13.14 restore/build/test on the approved runner; Flutter analyze/test and Android real-device matrix; Terraform provider initialization and target-account plan; Helm lint/render/kubeconform with installed CRDs; model artifact build/signature/license/benchmark; live AWS/Stripe/attestation integration; load/soak/chaos/pentest; backup restore and regional DR; legal/finance/privacy approvals; and production canary evidence.

These are not design ambiguities. They are explicit, owned, machine-typed release gates. The production gate fails when any required evidence is absent, duplicated, expired, mismatched, or not bound to the exact release.
