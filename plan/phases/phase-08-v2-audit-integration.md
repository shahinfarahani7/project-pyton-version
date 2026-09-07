# Phase 8 — Architecture v2 Audit Integration

> **Architecture ref:** Sections 72–77, extended §69, revised §65–70  
> **Authority:** [EDGE-MINT-TARGET-ARCHITECTURE-v2.md](../docs/EDGE-MINT-TARGET-ARCHITECTURE-v2.md)  
> **Depends on:** Phase 7 complete (v1-plan scope)  
> **Blocks:** v2 production closure (§69 additional items, §73 policy readiness)

## Objective

Close the gap between Phase 0–7 implementation (v1-plan scope) and v2 audit-integrated requirements A01–A24 / acceptance cases T01–T24. v2 **documents** requirements; this phase produces evidence.

---

## Meta tasks

### P8-T01 — Adopt v2 as canonical authority

- **Status:** done
- **Objective:** Point governance, canonical decisions, and START-HERE to v2; mark v1 superseded.
- **Impacted paths:** `docs/`, `plan/`, `production/canonical-decisions.yaml`, `START-HERE.md`, `.cursor/rules/`
- **Acceptance criteria:** No active authority pointer remains on v1; v1 banner shows superseded.
- **Evidence:** `plan/evidence/phase-08-p8-t01-v2-authority-adoption.json`
- **Rollback:** Revert authority pointers (not recommended).

---

### P8-T02 — Audit traceability matrix (A01–A24)

- **Status:** done
- **Depends on:** P8-T01
- **Objective:** Seed [audit-matrix.md](../audit-matrix.md) v2 section mapping A01–A24 → sections → T-cases.
- **Evidence:** `plan/audit-matrix.md` § v2 audit integration
- **Rollback:** Remove v2 audit section.

---

### P8-T03 — Acceptance scenarios registry (T01–T24)

- **Status:** done
- **Depends on:** P8-T01
- **Objective:** Create machine-readable registry of §74 cases with NOT RUN baseline.
- **Evidence:** `plan/evidence/phase-08-p8-t03-acceptance-scenarios-registry.json`
- **Rollback:** Delete registry file.

---

### P8-T04 — Policy readiness gate gap analysis (§73)

- **Status:** done
- **Depends on:** P8-T01
- **Objective:** Inventory required production policy values; classify missing vs configured.
- **Evidence:** `plan/evidence/phase-08-p8-t04-policy-readiness-gap.json`; `tools/analyze_v2_policy_readiness.py`
- **Rollback:** N/A.

---

### P8-T05 — Current-state evidence register baseline (§75)

- **Status:** done
- **Depends on:** P8-T01
- **Objective:** Pin checkout, catalog snapshot, artifact digests for each §75 claim.
- **Evidence:** `plan/evidence/phase-08-p8-t05-current-state-register.json`; `tools/analyze_v2_current_state_register.py`
- **Rollback:** N/A.

---

### P8-T06 — Active model identity investigation (§76)

- **Status:** done
- **Depends on:** P8-T05
- **Objective:** Source-static investigation of identity loop symbols; device repro deferred to P8-A22/T22.
- **Evidence:** `plan/evidence/phase-08-p8-t06-identity-loop-investigation.json`; `tools/investigate_v2_identity_loop.py`
- **Rollback:** N/A.

---

### P8-T07 — Phase 8 exit: v2 audit integration sign-off

- **Status:** done
- **Depends on:** All P8-A* tasks, P8-T04–P8-T06
- **Objective:** All §69 v2 additional items checked or explicitly deferred with evidence.
- **Evidence:** `plan/evidence/phase-08-p8-t07-v2-closure-signoff.json`; `tools/verify_phase8_v2_closure_signoff.py`
- **Classification:** IMPLEMENTED_DEV_ONLY — A01–A24 dev evidence complete; §74 T12–T24 NOT_RUN; production gate CLOSED.
- **Rollback:** Reopen phase.

---

## Audit finding tasks (A01–A24)

Each task closes one audit finding from §72. Status starts `pending`. Acceptance case in parentheses.

| Task ID | Audit ID | Requirement summary | Case |
|---------|----------|---------------------|------|
| P8-A01 | A01 | TaskRun/Attempt/Assignment identities; terminal-race CAS | T01 |
| P8-A02 | A02 | Bounded grant, fencing, stop, physical release | T02 |
| P8-A03 | A03 | Durable delivery, Inbox, ACK, replay, bootstrap | T03 |
| P8-A04 | A04 | Resident/base/peak memory accounting | T04 |
| P8-A05 | A05 | Static envelope vs per-input ExecutionAllocation | T05 |
| P8-A06 | A06 | Contribution units, explicit consent, bounded enforcement | T06 |
| P8-A07 | A07 | Tenant/data trust; permitted Cloud | T07 |
| P8-A08 | A08 | Validation/reward uniqueness; external effects | T08 |
| P8-A09 | A09 | Local bounded Plan; transport recovery boundary | T09 |
| P8-A10 | A10 | Artifact-bound Context; output enforcement | T10 |
| P8-A11 | A11 | Bounded hierarchical reduce; semantic merge | T11 |
| P8-A12 | A12 | Checkpoint provenance; fresh ResumeGrant | T12 |
| P8-A13 | A13 | Runtime-pair conflicts; bounded light work | T13 |
| P8-A14 | A14 | Scoped retries; affinity; no-Worker handling | T14 |
| P8-A15 | A15 | Unique catalog; taxonomy; Flex gates | T15 |
| P8-A16 | A16 | Reproducible artifact/install/runtime identity | T16 |
| P8-A17 | A17 | Physical-device process lifecycle proof | T17 |
| P8-A18 | A18 | Contract-specific quality validation | T18 |
| P8-A19 | A19 | DRR fairness; backpressure; operating signals | T19 |
| P8-A20 | A20 | Versioned calibration/prediction | T20 |
| P8-A21 | A21 | Bounded decode; cleanup/privacy | T21 |
| P8-A22 | A22 | Active identity loop; Native crash evidence | T22 |
| P8-A23 | A23 | Dependency gates; mixed-version rollout | T23 |
| P8-A24 | A24 | Runtime maintenance; evaluated upgrade/rollback | T24 |

Task blocks use the standard template; detail in [audit-matrix.md](../audit-matrix.md) v2 section.

**Default status for P8-A02 … P8-A24:** `pending`  
**Default evidence path:** `plan/evidence/phase-08-p8-a{nn}-{slug}.json`

---

### P8-A01 — TaskRun/terminal-race ownership (A01 / T01)

- **Status:** done
- **Objective:** Distinct TaskRun identity from TaskRevision; atomic terminal transition CAS for cancel/complete races.
- **Evidence:**
  - SQL: `database/sql/025_task_runs_terminal_cas.sql`
  - Service: `src/backend/edgemint/tasks/task_run.py`
  - Wiring: `src/backend/edgemint/tasks/admission.py`, `src/backend/edgemint/workers/assignments.py`
  - Tests: `src/backend/tests/tasks/test_task_run_terminal_cas.py` (6 passed)
  - Validator: `tools/verify_task_run_terminal_cas.py`
  - Artifact: `plan/evidence/phase-08-p8-a01-task-run-terminal-cas.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T01 concurrent integration harness NOT_RUN; `task_attempts.task_run_id` link on attempt creation pending.

---

### P8-A02 — Bounded grant, fencing, stop, physical release (A02 / T02)

- **Status:** done
- **Objective:** Distinguish stop requested vs stop confirmed; track physical release independently of logical reservation; block conflicting work on uncertain holds.
- **Evidence:**
  - SQL: `database/sql/026_worker_physical_release.sql`
  - Service: `src/backend/edgemint/routing/physical_release.py`
  - Wiring: `resource_reservations.py`, `exclusive_groups.py`, `assignments.py`, `worker_registry.py`
  - Worker: `execution_stop_tracker.dart`, `assignment_coordinator.dart`
  - Tests: `test_physical_release.py` (4 passed); Dart test present (pub.dev network blocked execution)
  - Upstream: `phase-07-p7-chaos-stale-fence-writes.json`, `phase-07-p7-chaos-lease-expiry.json`
  - Validator: `tools/verify_physical_release_grant.py`
  - Artifact: `plan/evidence/phase-08-p8-a02-physical-release-grant.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T02 integration harness and Native uninterruptible proof NOT_RUN.

---

### P8-A03 — Durable delivery, Inbox, ACK, replay, bootstrap (A03 / T03)

- **Status:** done
- **Objective:** Durable assignment delivery inbox with idempotent record/ACK and reconnect bootstrap reconciliation.
- **Evidence:**
  - SQL: `database/sql/027_worker_assignment_delivery_inbox.sql`
  - Server: `assignment_delivery_inbox.py`, wired in `assignments.py` + `GET /assignments:inboxBootstrap`
  - Worker: `assignment_inbox.dart`, `assignment_coordinator.dart` reconcile/duplicate guards
  - WS path upstream: `transactional_inbox.py`, `verify_websocket_replay_source.py`
  - Tests: `test_assignment_delivery_inbox.py` + `test_eventing_contracts.py` (10 passed)
  - Validator: `tools/verify_assignment_delivery_inbox.py`
  - Artifact: `plan/evidence/phase-08-p8-a03-assignment-delivery-inbox.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T03 live crash/ACK-loss harness NOT_RUN; OpenAPI sync pending.

---

### P8-A04 — Resident/base/peak memory accounting (A04 / T04)

- **Status:** done
- **Objective:** One consistent accounting basis for base runtime, resident models, and task peaks without double-counting shared resident memory.
- **Evidence:**
  - SQL: `database/sql/028_worker_memory_accounting.sql`
  - Service: `src/backend/edgemint/routing/memory_accounting.py`
  - Wiring: `resource_reservations.py`, `enrollment.py` heartbeat sync, worker `memory_accounting.dart`
  - Tests: `test_memory_accounting.py` (4 passed)
  - Validator: `tools/verify_memory_accounting.py`
  - Artifact: `plan/evidence/phase-08-p8-a04-memory-accounting.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T04 dual-scheduler integration harness NOT_RUN.

---

### P8-A05 — Static envelope vs per-input ExecutionAllocation (A05 / T05)

- **Status:** done
- **Objective:** Separate immutable Revision ResourceEnvelope from server-derived per-input ExecutionAllocation; assignment references allocation not static envelope alone.
- **Evidence:**
  - SQL: `database/sql/029_task_execution_allocations.sql`
  - Service: `src/backend/edgemint/routing/execution_allocation.py`
  - Wiring: `src/backend/edgemint/tasks/admission.py`, `src/backend/edgemint/routing/atomic_assignment.py`
  - Tests: `src/backend/tests/routing/test_execution_allocation.py` (4 passed)
  - Validator: `tools/verify_execution_allocation.py`
  - Artifact: `plan/evidence/phase-08-p8-a05-execution-allocation.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T05 admission→assignment integration harness NOT_RUN; create_revision path pending TaskRun/allocation mint.

---

### P8-A06 — Contribution units, explicit consent, bounded enforcement (A06 / T06)

- **Status:** done
- **Objective:** Versioned 30/50 contribution profiles with explicit opt-in, windowed CPU enforcement profile, and certified stop reaction bound on consent decrease/revocation.
- **Evidence:**
  - Policy: `dsl/policies/consent/production-resource-policy-v1.yaml` (`cpuEnforcement`, `contributionRequiresExplicitOptIn`)
  - SQL: `database/sql/030_worker_cpu_enforcement_certification.sql`
  - Services: `contribution_enforcement.py`, `consent_transitions.py`, `consent_opt_in.py`
  - Wiring: `enrollment.py` heartbeat certification sync, `hard_eligibility.py` optional gate
  - Worker: `contribution_enforcement.dart`, `worker_resource_enforcer.dart` telemetry
  - Tests: `test_contribution_enforcement.py`, `test_consent_opt_in.py`, `test_resource_policy.py` (13 passed)
  - Upstream: P6-T08/T09/T10, P7-CHAOS-consent-* evidence
  - Validator: `tools/verify_contribution_consent_enforcement.py`
  - Artifact: `plan/evidence/phase-08-p8-a06-contribution-consent-enforcement.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T06 live inference revocation harness NOT_RUN; Native stop certification NOT_RUN.

---

### P8-A07 — Tenant/data trust and permitted Cloud (A07 / T07)

- **Status:** done
- **Objective:** Fail-closed tenant scope, data-owner processing permission, worker credential trust, and Cloud fallback gated by data policy—not timer alone.
- **Evidence:**
  - Policy: `dsl/policies/data/production-data-policy-v1.yaml`
  - SQL: `database/sql/031_workspace_data_trust.sql`
  - Services: `data_policy_registry.py`, `tenant_data_trust.py`, `workspace_data_trust.py`
  - Wiring: `admission.py`, `cloud_fallback.py`, `sessions.py` (revoked session + device trust)
  - Tests: `test_tenant_data_trust.py`, `test_cloud_fallback.py` (10 passed)
  - Validator: `tools/verify_tenant_data_trust.py`
  - Artifact: `plan/evidence/phase-08-p8-a07-tenant-data-trust.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T07 end-to-end wrong-tenant artifact harness NOT_RUN.

---

### P8-A08 — Validation/reward uniqueness and external effects (A08 / T08)

- **Status:** done
- **Objective:** Immutable ResultCandidate pinning, validation-gated acceptance CAS, unique RewardEntitlement per TaskRun component, and destination-scoped external-effect dedup receipts.
- **Evidence:**
  - SQL: `database/sql/032_result_candidates_reward_entitlements.sql`
  - Services: `result_acceptance.py`, `entitlement_keys.py`, `external_effects.py`
  - Wiring: `assignments.py` complete path (pin → validate → accept + entitlement); `billing/service.py` idempotency replay
  - Tests: `test_result_acceptance.py` (6 passed); P7 `test_p7_chaos_reward_exactly_once` regression
  - Validator: `tools/verify_validation_reward_uniqueness.py`
  - Artifact: `plan/evidence/phase-08-p8-a08-validation-reward-uniqueness.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T08 crash-between-commit/entitlement/payout harness NOT_RUN.

---

### P8-A09 — Local bounded Plan and transport recovery boundary (A09 / T09)

- **Status:** done
- **Objective:** Worker may retransmit same transport identity without rerunning inference; transport recovery does not grant task retry/scheduling authority; bounded Plan policy documented.
- **Evidence:**
  - Policy: `dsl/policies/worker/transport-recovery-boundary-v1.yaml`
  - SQL: `database/sql/033_assignment_transport_receipts.sql`
  - Services: `transport_recovery.py`
  - Wiring: `assignments.py` progress/checkpoint replay; worker `transport_recovery_journal.dart`, `assignment_event_reporter.dart`
  - Tests: `test_transport_recovery.py`, `test_assignment_progress_checkpoint.py` (8 passed); worker journal test (flutter skipped on CI host)
  - Upstream: P3-T20 forbidden scheduler audit
  - Validator: `tools/verify_transport_recovery_boundary.py`
  - Artifact: `plan/evidence/phase-08-p8-a09-transport-recovery-boundary.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T09 lost-ACK/result E2E harness NOT_RUN.

---

### P8-A10 — Artifact-bound Context and output enforcement (A10 / T10)

- **Status:** done
- **Objective:** Count fully formatted prompts against `min(artifact, runtime, taskPolicy)` context limit; enforce max output tokens; truncated JSON is not silent success.
- **Evidence:**
  - DSL: `dsl/catalog/context-profiles/qwen2.5-0.5b-artifact-v1.yaml`
  - Backend: `context_profile_registry.py`, `context_budget.py`; `execution_allocation.py` output cap
  - Worker: `context_budget_manager.dart`, `formatted_prompt_builder.dart`, `output_limit_enforcer.dart`, `qwen_task_processor.dart`
  - Tests: `test_context_budget.py` (6 passed); `formatted_prompt_boundary_test.dart` (flutter skipped on host)
  - Upstream: P3-T04 context budget manager
  - Validator: `tools/verify_context_output_enforcement.py`
  - Artifact: `plan/evidence/phase-08-p8-a10-context-output-enforcement.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T10 native tokenizer exact-count harness NOT_RUN.

---

### P8-A11 — Bounded hierarchical reduce and semantic merge (A11 / T11)

- **Status:** done
- **Objective:** Server-authorized reduce bounds (`maxChunks`, `maxReduceDepth`, `maxInferenceCalls`); measurable progress rule; non-shrinking reduce stops with evidence.
- **Evidence:**
  - DSL: `dsl/catalog/execution-plans/text-summarize-map-reduce.yaml` (`reduceBounds`)
  - Backend: `hierarchical_reduce_policy.py`
  - Worker: `hierarchical_reduce_bounds.dart`, `semantic_merge_validator.dart`, `hierarchical_summarize_pipeline.dart`
  - Wiring: `failure_evidence.dart` maps reduce exhaustion/no-progress
  - Tests: `test_hierarchical_reduce_bounds.py` (6 passed); worker bounds tests (flutter skipped on host)
  - Upstream: P3-T07 map/reduce, P7-CHAOS-recursive-reduce
  - Validator: `tools/verify_hierarchical_reduce_bounds.py`
  - Artifact: `plan/evidence/phase-08-p8-a11-hierarchical-reduce-bounds.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T11 very-long-document E2E harness NOT_RUN.

---

### P8-A12 — Checkpoint provenance and fresh ResumeGrant (A12 / T12)

- **Status:** done
- **Objective:** Immutable checkpoint manifest on accepted chunk checkpoint; authenticated ResumeGrant binds authorized ranges to fresh Assignment; producer fence is provenance only.
- **Evidence:**
  - SQL: `database/sql/034_checkpoint_resume_grants.sql`
  - Backend: `checkpoint_resume.py`; wired in `assignments.py` (`publish_manifest` on chunk checkpoint)
  - Worker: `resume_grant.dart`, `checkpoint_manager.dart` (cross-Assignment resume via grant)
  - Wiring: `failure_evidence.dart` maps `ResumeGrantRejectedException` → `CHECKPOINT_INCOMPATIBLE`
  - Tests: `test_checkpoint_resume.py` (6 passed); worker grant tests (flutter skipped on host)
  - Upstream: P3-T08 fence-aware checkpoint, P7-CHAOS-chunk-resume
  - Validator: `tools/verify_checkpoint_resume_grant.py`
  - Artifact: `plan/evidence/phase-08-p8-a12-checkpoint-resume-grant.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T12 cross-Worker reassignment E2E harness NOT_RUN.

---

### P8-A13 — Runtime-pair conflicts and bounded light work (A13 / T13)

- **Status:** done
- **Objective:** Enforce runtime co-run matrix (Qwen+VLM blocked; certified Qwen+OCR exception); exclusive groups; light network/system work during heavy LLM.
- **Evidence:**
  - DSL: `production-v1.yaml` (runtime compatibility), `production-exclusive-groups-v1.yaml`
  - Backend: `runtime_compatibility.py`, `exclusive_groups.py`
  - Worker: `runtime_exclusive_group_enforcer.dart`
  - Tests: `test_runtime_pair_light_work.py` (5 passed); adaptive + exclusive group tests; worker enforcer (flutter skipped on host)
  - Upstream: P6-T05, P6-T13, P2-T16
  - Validator: `tools/verify_runtime_pair_light_work.py`
  - Artifact: `plan/evidence/phase-08-p8-a13-runtime-pair-light-work.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T13 transfer/control-message load harness NOT_RUN.

---

### P8-A14 — Scoped retries, affinity, and no-Worker handling (A14 / T14)

- **Status:** done
- **Objective:** Cause-scoped retry taxonomy; TaskRun-wide assignment/attempt/cloud budgets that never reset; failure and artifact affinity; no-Worker → new Attempt before Cloud.
- **Evidence:**
  - DSL: `smart-router-v2.yaml` (`taskRunBudget`, `countersResetOnNewAttempt: false`)
  - SQL: `database/sql/035_task_run_budgets.sql`
  - Backend: `task_run_budget.py`, `artifact_affinity.py`; wired in `service.py`, `cloud_fallback.py`, `hard_eligibility.py`
  - Tests: `test_scoped_retry_affinity.py` (9 passed); retry classifier + failure affinity regression
  - Upstream: P4-T05, P4-T11, P4-T12
  - Validator: `tools/verify_scoped_retry_affinity.py`
  - Artifact: `plan/evidence/phase-08-p8-a14-scoped-retry-affinity.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T14 exhausted-Attempt E2E harness NOT_RUN.

---

### P8-A15 — Catalog reconciliation and Flex gates (A15 / T15)

- **Status:** done
- **Objective:** Reconcile unique catalog snapshot against historical 56; document overlapping taxonomy axes; gate Flex dispatch on complete flexInput contract + worker handler.
- **Evidence:**
  - Module: `catalog_reconciliation.py`; wired in `catalog_closure.py` (`validate_queue_admission`)
  - DSL gate: `validate_dsl.py` uses flex dispatch violations (v2 §57)
  - Snapshot: 56 unique IDs, 9 flex dispatchable, 7 orphan DSL stubs documented
  - Tests: `test_catalog_reconciliation.py` (7 passed); `validate_catalog_closure.py` regression
  - Upstream: P0-T06, P5-GAP-08, P8-T05
  - Validator: `tools/verify_catalog_reconciliation_flex_gates.py`
  - Artifact: `plan/evidence/phase-08-p8-a15-catalog-reconciliation-flex-gates.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T15 duplicate-ID negative injection harness NOT_RUN.

---

### P8-A16 — Reproducible artifact/install/runtime identity (A16 / T16)

- **Status:** done
- **Objective:** Bind Qwen artifact identity (ekv1280, modelVersionId, context limit); serialize install/verify; block concurrent install and upgrade during open sessions; reject bad digest/signature.
- **Evidence:**
  - DSL: `qwen2.5-0.5b-artifact-v1.yaml`
  - Backend: `artifact_identity.py`
  - Worker: `artifact_install_coordinator.dart`, wired in `worker_model_installer.dart` + `model_runtime_manager.dart`
  - Upstream: P3-T16 verify hook, P8-A10 context profile
  - Tests: `test_artifact_identity.py` (4 passed); coordinator/verifier tests (flutter skipped on host)
  - Validator: `tools/verify_artifact_install_runtime_identity.py`
  - Artifact: `plan/evidence/phase-08-p8-a16-artifact-install-runtime-identity.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T16 interrupted download / device concurrent install NOT_RUN.

---

### P8-A17 — Physical-device process lifecycle proof (A17 / T17)

- **Status:** done
- **Objective:** Define Android process lifecycle profile; invalidate native handles on process death/reboot; block stale checkpoint resume until fresh server grant; document physical-device T17 matrix.
- **Evidence:**
  - DSL: `dsl/policies/worker/android-process-lifecycle-v1.yaml`
  - Backend: `physical_device_proof.py`
  - Worker: `process_lifecycle_coordinator.dart`, wired in `worker_app_controller.dart`, `main.dart`, `assignment_coordinator.dart`
  - Native: `ExecutionForegroundService.kt`, `AndroidManifest.xml`
  - Runbook: `docs/08-sre/runbooks/RB-023-physical-device-lifecycle-proof.md`
  - Tests: `test_physical_device_lifecycle.py` (4 passed); coordinator tests (flutter skipped on host)
  - Validator: `tools/verify_physical_device_lifecycle_proof.py`
  - Artifact: `plan/evidence/phase-08-p8-a17-physical-device-lifecycle-proof.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T17 physical-device harness NOT_RUN; emulator alone cannot certify production.

---

### P8-A18 — Contract-specific semantic quality validation (A18 / T18)

- **Status:** done
- **Objective:** Distinguish schema/business validation from semantic quality; reject contract-valid wrong content; ignore self-reported confidence as sole proof; keep quality escalation distinct from capacity.
- **Evidence:**
  - DSL: `dsl/policies/validation/semantic-quality-v1.yaml`
  - Backend: `semantic_quality.py`, wired in `validator.py`; `quality_escalation.py` escalation classes
  - Upstream: P5-CROSS-01 validation framework
  - Tests: `test_semantic_quality_validation.py` (6 passed); `test_quality_escalation.py` (3 passed)
  - Validator: `tools/verify_semantic_quality_validation.py`
  - Artifact: `plan/evidence/phase-08-p8-a18-semantic-quality-validation.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T18 full golden wrong-output matrix NOT_RUN.

---

### P8-A19 — DRR fairness, backpressure and operating signals (A19 / T19)

- **Status:** done
- **Objective:** Workspace DRR deficit accounting; per-workspace/pipeline admission caps; distinct blocked reasons; operating signals for queue age and blockers.
- **Evidence:**
  - DSL: `dsl/policies/scheduling/workspace-admission-backpressure-v1.yaml`
  - Backend: `workspace_drr.py`, `admission_backpressure.py`, `operating_signals.py`
  - Wiring: `RouterService.compute_queue_cost_units`, `evaluate_admission_backpressure`, `collect_operating_signals`, `rank_task_attempts_with_drr`
  - Upstream: P4-T06 fair queue ordering, fair queue metrics
  - Tests: `test_drr_fairness_backpressure.py` (6 passed) + fair queue tests (6 passed)
  - Validator: `tools/verify_drr_fairness_backpressure.py`
  - Artifact: `plan/evidence/phase-08-p8-a19-drr-fairness-backpressure.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T19 multi-workspace saturation harness NOT_RUN.

---

### P8-A20 — Versioned calibration/prediction (A20 / T20)

- **Status:** done
- **Objective:** Versioned prediction records; profile expiry/conservative fallback; cold/warm phase distinction; future-only feedback without retroactive grant increase.
- **Evidence:**
  - DSL: `dsl/policies/calibration/versioned-prediction-v1.yaml`
  - Backend: `calibration_prediction.py`; extended `calibration.py`, `RouterService.build_versioned_prediction_record`
  - Upstream: P6-T03 calibration loop, P6-T07 prediction feedback, P2-T04 calibration persistence
  - Tests: `test_versioned_calibration_prediction.py` (6 passed) + adaptive/calibration feedback tests (12 passed)
  - Validator: `tools/verify_versioned_calibration_prediction.py`
  - Artifact: `plan/evidence/phase-08-p8-a20-versioned-calibration-prediction.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T20 cold/warm E2E allocation proof NOT_RUN.

---

### P8-A21 — Bounded decode, cleanup and privacy (A21 / T21)

- **Status:** done
- **Objective:** Reject oversized decoded inputs before admission; reject partial uploads; assignment-scoped temp cleanup; preserve checkpoint on cancel/resume; prevent cross-task buffer leakage.
- **Evidence:**
  - DSL: `dsl/policies/data/input-decode-privacy-v1.yaml`
  - Backend: `input_decode_bounds.py`, `artifact_privacy.py`; wired in `admission.py`, `lifecycle.py`
  - Worker: `privacy_cleanup_coordinator.dart`, wired in `assignment_coordinator.dart`
  - Upstream: P3-T17 storage pressure manager
  - Tests: `test_input_decode_privacy.py` (8 passed); privacy coordinator tests (flutter skipped on host)
  - Validator: `tools/verify_decode_bounds_privacy_cleanup.py`
  - Artifact: `plan/evidence/phase-08-p8-a21-decode-bounds-privacy-cleanup.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T21 E2E decode/cancel race NOT_RUN.

---

### P8-A22 — Active identity loop and Native crash evidence (A22 / T22)

- **Status:** done
- **Objective:** Causal identity mutation traces with Native handle counters; server-side Native crash reconciliation without Dart after SIGSEGV; heartbeat `identityLifecycleView`.
- **Evidence:**
  - DSL: `dsl/policies/worker/active-identity-native-lifecycle-v1.yaml`
  - Worker: `identity_lifecycle_tracer.dart`; wired in installer, runtime manager, app controller, lifecycle coordinator
  - Backend: `identity_native_lifecycle.py`; extended heartbeat schemas
  - Upstream: P8-T06 source investigation, P8-A17 process lifecycle
  - Runbook: `docs/08-sre/runbooks/RB-024-identity-loop-native-crash-evidence.md`
  - Tests: `test_identity_native_lifecycle.py` (7 passed); tracer tests (flutter skipped on host)
  - Validator: `tools/verify_identity_loop_native_crash.py`
  - Artifact: `plan/evidence/phase-08-p8-a22-identity-loop-native-crash.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T22 idle soak and Native crash regression NOT_RUN.

---

### P8-A23 — Policy gates and mixed-version rollout (A23 / T23)

- **Status:** done
- **Objective:** Fail-closed §73 activation gate with PolicyReadinessRecord; dependency evidence checks; mixed-version rollout and storage-restore dedup evaluation.
- **Evidence:**
  - DSL: `dsl/policies/governance/policy-readiness-gate-v1.yaml`
  - Schema: `dsl/schemas/policyreadinessrecord.schema.json`
  - SQL: `database/sql/036_policy_readiness_records.sql`
  - Backend: `src/backend/edgemint/governance/policy_readiness_gate.py`
  - Upstream: P8-T04 gap analysis, P8-T05 current-state register
  - Runbook: `docs/08-sre/runbooks/RB-026-policy-readiness-mixed-version-gate.md`
  - Tests: `test_policy_readiness_gate.py` (7 passed)
  - Validator: `tools/verify_policy_readiness_gates.py`
  - Artifact: `plan/evidence/phase-08-p8-a23-policy-readiness-gates.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — production gate CLOSED; T23 integration harness NOT_RUN.

---

### P8-A24 — Runtime maintenance and evaluated upgrade (A24 / T24)

- **Status:** done
- **Objective:** Pin maintenance status; evaluate candidate runtime/model upgrades; require rollback before adoption; block upgrade during open sessions.
- **Evidence:**
  - DSL: `dsl/policies/runtime/runtime-maintenance-upgrade-v1.yaml`
  - SQL: `database/sql/037_runtime_upgrade_evaluations.sql`
  - Backend: `src/backend/edgemint/runtime/runtime_upgrade_policy.py`
  - Worker: `runtime_upgrade_coordinator.dart`; gemma runtime manager upgrade guard
  - Upstream: P8-A16, model promotion gate
  - Runbook: `docs/08-sre/runbooks/RB-027-runtime-maintenance-upgrade-evaluation.md`
  - Tests: `test_runtime_upgrade_policy.py` (6 passed); coordinator tests (flutter skipped on host)
  - Validator: `tools/verify_runtime_upgrade_compatibility.py`
  - Artifact: `plan/evidence/phase-08-p8-a24-runtime-upgrade-compatibility.json`
- **Classification:** IMPLEMENTED_DEV_ONLY — T24 candidate runtime device evaluation NOT_RUN.

---

## Notes

- Phase 0–7 plan tasks remain valid historical work under v1-plan scope.
- v2 §65 preserves phase numbers but adds stricter activation gates (§73).
- Do not mark P8-A* complete without the matching T-case evidence per §74.
