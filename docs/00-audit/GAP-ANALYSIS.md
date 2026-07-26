# EdgeMint v1 Gap Analysis and Remediation

## Audit scope

The v1 archive contained 951 files and roughly 631k lines. Most lines were JSONL vectors. The audit evaluated whether those assets were sufficient to implement and operate a production system without inventing missing behavior.

## Critical findings

| ID | Severity | v1 gap | Production impact | v2 remediation |
|---|---|---|---|---|
| GAP-001 | Critical | DSL validator checked only four envelope fields | malformed policies passed CI | strict per-kind JSON Schema plus cross-reference and semantic validation |
| GAP-002 | Critical | no schema existed for `NotificationTemplate` | active manifests had no enforceable contract | schema added and all active kinds mapped |
| GAP-003 | Critical | 595k vectors were checked only for valid JSON | mathematically wrong expectations could pass | executable policy oracles recompute every expected result |
| GAP-004 | Critical | pricing vectors could fall below declared minimum charge | revenue leakage and inconsistent invoices | integer micro-EUR pipeline and explicit floor/subsidy order |
| GAP-005 | Critical | reward currency was an undefined floating `EDGE_OFFCHAIN` | token volatility leaked into COGS and liabilities | rewards accrue in EUR micros; token conversion occurs only in claim epochs |
| GAP-006 | Critical | ledger posting rules were incomplete | reserves, refunds, claims and processor settlement could not reconcile | full posting catalog, clearing accounts and task financial invariant |
| GAP-007 | Critical | task state mixed task, attempt, assignment and verification | retries, lease expiry and edit behavior were ambiguous | separate state machines and explicit aggregate ownership |
| GAP-008 | Critical | assignment distribution required automatic lease/fencing semantics | duplicate execution and double payout | atomic server-side auto-lease, automatic start, lease renewal and fencing-token contract |
| GAP-009 | High | public API omitted files finalization, cancel, results, webhooks, keys, team, billing and disputes | panel and integrations required invented endpoints | complete public API baseline with standard errors and idempotency |
| GAP-010 | High | worker API omitted challenge auth, machine unavailability, lease renew, checkpoint, uploads, earnings and claim | mobile implementation could not recover safely | complete worker protocol and API |
| GAP-011 | High | database had minimal tables and weak constraints | no tenant isolation, quote, result, verification, entitlement or webhook persistence | complete PostgreSQL migration set, row-level security, indexes, constraints, and session-context enforcement |
| GAP-012 | High | reference Python handler threw `NotImplementedException` | not an executable reference flow | deterministic reference engines and orchestration interfaces |
| GAP-013 | High | infrastructure consisted of three skeletal files | no realistic deployment topology | Docker development topology, Kubernetes workloads/policies and Terraform contract |
| GAP-014 | High | security controls and runbooks were generic copies | operators could not execute incidents | control-specific evidence and incident-specific decision steps |
| GAP-015 | High | use cases and scenarios were repetitive templates | false sense of coverage | authoritative domain-specific use cases and scenario matrix; old files archived |
| GAP-016 | High | model artifact sizes/hashes could be placeholders without blocking release | corrupt or wrong model could ship | model lifecycle states and production gate requiring digest, signature and benchmark evidence |
| GAP-017 | High | no task-to-API-to-event-to-table-to-test traceability | gaps could not be detected automatically | generated traceability registry and validator |
| GAP-018 | Medium | compiler output ordering was not byte-reproducible | recompilation invalidated package checksum | deterministic sorted compilation and manifest generation |
| GAP-019 | Medium | floating point appeared in prices, rewards and percentages | cross-language rounding divergence | integer micros and basis points throughout |
| GAP-020 | Medium | legal statements were mixed with implementation assumptions | launch team could mistake architecture for legal approval | hard compliance gates and jurisdiction decision register |

## Deliberate non-claims

No static package can eliminate unknown future legal decisions, actual model benchmark results, payment-provider terms, App Store review outcomes or jurisdiction-specific tax treatment. v2 makes these explicit release blockers with owners and evidence fields instead of silently guessing.

## Additional contradiction found during v2 closure audit

| ID | Severity | pre-closure gap | Production impact | remediation |
|---|---|---|---|---|
| GAP-021 | Critical | the public `Task.status` and Python reference aggregate still mixed customer lifecycle, billing reservation and execution/attempt states despite the ownership contract | clients and services could perform invalid transitions, overwrite execution evidence or infer charging from execution status | public API now requires separate `lifecycleStatus`, `executionStatus` and `billingStatus`; Python Task and Attempt aggregates were aligned to their independent DSL state machines; CI rejects a generic Task `status` field |
| GAP-022 | High | Python pricing and routing examples used fewer modifiers, different weights and different eligibility limits than active DSL | teams copying the reference implementation would produce different prices and worker selections than test vectors | reference engines now consume the complete ordered policy and exact DSL feature set; semantic vector oracles independently validate all policy outputs |
| GAP-023 | Critical | persisted PostgreSQL state constraints for Task, Attempt, Claim and Reward differed from active DSL state machines | persisted states could not be replayed through the authoritative transition rules | PostgreSQL CHECK constraints and columns now exactly match DSL; validation compares them automatically |
| GAP-024 | Critical | ledger balance existed as a callable function but was not enforced automatically | unbalanced transactions could commit if application code omitted the call | a deferred constraint trigger checks every affected ledger transaction at commit |
| GAP-025 | High | tenant RLS covered only four top-level tables | child records could be exposed by a query that missed an application tenant predicate | RLS and FORCE RLS now cover all customer-owned top-level and child tables through workspace/organization joins |
| GAP-026 | High | token conversion used an unconstrained decimal rate | implementations could round differently and liabilities could drift | ClaimEpoch now stores an integer rational rate and mandates floor conversion with retained residual balance |
| GAP-027 | High | Kubernetes workloads referenced absent ServiceAccounts/ConfigMap and had no PDB/HPA contract | base manifests could not be rendered or operated consistently | namespace, service accounts, common config, network baseline, PDBs, HPAs, topology spread and infrastructure validator added |
| GAP-028 | High | provider-neutral Terraform interfaces could be mistaken for deployable production IaC | teams could apply an incomplete environment with invented defaults | infrastructure is now explicitly classified as a provider-neutral contract; production overlay evidence and provider decision are hard release blockers |
| GAP-029 | Critical | EventCatalog contained duplicate aliases, double namespace prefixes and dot/underscore variants; AsyncAPI omitted two CloudEvent types | producers and consumers could publish/subscribe to different topics for the same business fact | event registry canonicalized from 220 aliases to 186 unique event types; CloudEvent examples and AsyncAPI are regenerated one-to-one; CI enforces exact set equality |

## Contract-closure findings from the second audit pass

| ID | Severity | gap found in the first v2 build | Production impact | remediation now included |
|---|---|---|---|---|
| GAP-030 | Critical | UseCase files referenced operation names that did not exist in OpenAPI, while the stricter schema required an implementation block that most files lacked | implementation teams would invent endpoint mappings, permissions and transaction boundaries | all 60 business UseCases now contain exact transport, authorization, idempotency, transaction, concurrency, financial, error, observability and retention contracts; all references are validated against OpenAPI |
| GAP-031 | Critical | 16 required business operations were absent and several operation IDs used inconsistent plural, capitalization or hyphen conventions | generated SDKs and traceability tooling would diverge | 16 missing contracts were added, all 141 operation IDs are unique lowerCamelCase, and CI enforces naming plus permissions |
| GAP-032 | High | many supporting API operations had no machine-readable implementation contract even when a standalone business UseCase was unnecessary | CRUD/query behavior, audit rules and idempotency could be interpreted differently per service | one `OperationContract` DSL document is generated and validated for every OpenAPI operation, including method/path, permission, tenant boundary, writes, events, errors and use-case coverage |
| GAP-033 | Critical | persistence was missing invitations, attestation challenges, worker preferences and several operational support records | public and worker APIs could not be implemented transactionally | migration 021 adds operational tables, constraints and RLS; SQL validation now requires all 59 normative tables |
| GAP-034 | High | failure scenarios used generic error names not present in ErrorCatalog and all scenarios repeated the same prose | tests could pass without exercising a deterministic failure | 120 business scenarios now bind exact operation IDs, requirements, writes/events and canonical failure codes; traceability validation compares them with their UseCase |
| GAP-035 | Critical | `respectWorkerNetworkPolicy` existed in RoutingPolicy but was omitted from the routing oracle and Python reference | a worker could receive paid tasks against its data/network preference | oracle, 100k vectors and reference eligibility now include `networkPolicyAllowed` and `NETWORK_POLICY_BLOCKED` |
| GAP-036 | High | samples covered only the old 125 operations and sample validation checked only file existence and idempotency headers | SDK consumers had no authoritative examples for new commands | all 141 operations now have generated request/response samples; validator checks method, path, parameters, permissions, required body, success status and redaction |
| GAP-037 | High | reference code threw error strings that differed from ErrorCatalog | services could expose undocumented failure contracts | reference exceptions were canonicalized and static validation rejects uncatalogued domain error codes |
| GAP-038 | High | release blocker output omitted cloud image digests and most external decisions | an incomplete environment could appear production-ready | release blocker registry now aggregates 5 model gates, 3 finance gates, 19 image digest gates and 9 external decisions into one report |
| GAP-039 | Critical | traceability validation checked only requirement/use-case counts | mismatched events, tables, permissions, transport, scenarios and operation contracts could pass | validator now performs exact OpenAPI → OperationContract → UseCase → Scenario → EventCatalog → ErrorCatalog → SQL table cross-checks |
| GAP-040 | Medium | read-only UseCases inherited mutation-only idempotency acceptance text | clients could assume GET requests create idempotency records or side effects | read and mutation semantics are now generated separately and validated against HTTP method |

## Closure statement

All internally resolvable contradictions identified in this audit are closed by executable validators. Items dependent on a real provider, production binary, legal opinion, tax ruling, App Store decision or signed finance approval are not guessed; they are listed in `EXTERNAL-RELEASE-BLOCKERS.md` and remain hard production gates.
