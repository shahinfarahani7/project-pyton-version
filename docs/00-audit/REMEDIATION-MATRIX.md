# Remediation Matrix

Each gap is closed only when all evidence columns pass.

| Gap | Specification | DSL/Contract | Persistence | Automated evidence | Release gate |
|---|---|---|---|---|---|
| GAP-001/002 | DSL governance | strict schemas | policy registry | `tools/validate_dsl.py` | no invalid manifest |
| GAP-003/004 | pricing calculation order | PriceBook + CostModel | quote/usage tables | pricing oracle vectors | margin floor passes |
| GAP-005 | reward/claim separation | RewardPolicy + ClaimPolicy | accrual/epoch/claim tables | reward/claim oracles | treasury coverage |
| GAP-006 | double-entry postings | LedgerPolicy | ledger tables | ledger oracle + reconciliation | zero imbalance |
| GAP-007/008 | state and lease semantics | StateMachine + WorkerProtocol | attempts/assignments/checkpoints | lifecycle/resume vectors | no stale lease completion |
| GAP-009/010 | complete APIs | OpenAPI/AsyncAPI | corresponding entities | contract validator + samples | all required operations present |
| GAP-011 | data integrity | entity catalog | migrations + RLS | SQL static validation | migration review |
| GAP-012 | implementation reference | service specs | n/a | reference self-tests | no placeholder exception |
| GAP-013 | deployment | topology/SLO | n/a | manifest validation | staging soak test |
| GAP-014 | operations/security | controls/runbooks | audit/fraud tables | evidence matrix | security review |
| GAP-015/017 | coverage | use cases/scenarios | n/a | traceability validator | 100% critical requirements mapped |
| GAP-016 | model release | ModelProfile/ReleasePolicy | model artifacts | release blocker validator | signed digest and benchmark |
| GAP-018 | reproducibility | build rules | manifest | rebuild checksum test | deterministic build |
| GAP-019 | numeric determinism | money conventions | bigint columns | cross-language golden vectors | exact match |
| GAP-020 | compliance | compliance gates | evidence registry | manual approval evidence | legal sign-off |

| GAP-030/039/040 | executable use-case semantics | UseCase + Scenario + OperationContract | all traced tables | `tools/validate_traceability.py` | zero cross-contract errors |
| GAP-031/032 | API operation closure | OpenAPI + OperationContract | operation-specific entities | `tools/validate_contracts.py` + traceability | 1:1 operation contract coverage |
| GAP-033 | operational persistence | API/use-case entity trace | 59 required tables + RLS | `tools/validate_sql.py` | no missing table or tenant policy |
| GAP-034/036 | deterministic examples | Scenario + sample contracts | n/a | `tools/validate_samples.py` | all operations sampled and scenarios canonical |
| GAP-035/037 | reference parity | RoutingPolicy + ErrorCatalog | n/a | vector oracle + `tools/validate_reference.py` | exact policy/error parity |
| GAP-038 | release truthfulness | decision register | evidence references | `tools/validate_release_blockers.py` | unresolved external items remain blocked |
