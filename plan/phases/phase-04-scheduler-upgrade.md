# Phase 4 — Scheduler Upgrade

> **Architecture ref:** Section 65 Phase 4, Sections 7, 9–10, 36–38  
> **Depends on:** Phase 2 complete (Phase 3 parallel where noted)  
> **Blocks:** Phase 5–7 scheduling quality

## Objective

Upgrade server scheduler: hard feasibility, model locality, resource fit, scarcity cost, failure affinity, cooldown, deterministic scoring, routing audit, atomic reservation integration.

---

### P4-T01 — Hard eligibility filter

- **Status:** done
- **Depends on:** P2-T16, P2-T22
- **Objective:** Implement Hard Eligibility Filter in control plane pipeline (Sections 7, 10).
- **Impacted paths:** `src/backend/edgemint/routing/service.py`
- **Acceptance criteria:** Ineligible workers never reach scoring; unit tests for each gate.
- **Evidence:** `plan/evidence/phase-04-p4-t01-hard-eligibility-filter.json`; `src/backend/tests/routing/test_hard_eligibility_filter.py`
- **Rollback:** Bypass filter flag (dev only).

---

### P4-T02 — Model locality scoring

- **Status:** done
- **Depends on:** P0-T04, P4-T01
- **Objective:** Prefer workers with resident required model (Sections 5, 37).
- **Impacted paths:** `src/backend/edgemint/routing/service.py`, worker model reports
- **Acceptance criteria:** Worker with model ranked above cold worker; tie-break documented.
- **Evidence:** `plan/evidence/phase-04-p4-t02-model-locality-scoring.json`; `src/backend/tests/routing/test_model_locality_scoring.py`
- **Rollback:** Disable locality weight.

---

### P4-T03 — Resource fit scoring

- **Status:** done
- **Depends on:** P2-T06, P4-T01
- **Objective:** Score workers by resource envelope fit (Section 37).
- **Impacted paths:** routing service, reservation ledger
- **Acceptance criteria:** Insufficient capacity workers filtered or penalized per policy.
- **Evidence:** `plan/evidence/phase-04-p4-t03-resource-fit-scoring.json`; `src/backend/tests/routing/test_resource_fit_scoring.py`
- **Rollback:** N/A.

---

### P4-T04 — Fragmentation / scarcity cost

- **Status:** done
- **Depends on:** P4-T03
- **Objective:** Apply scarcity and fragmentation cost to scoring (Section 37).
- **Impacted paths:** `src/backend/edgemint/routing/service.py`
- **Acceptance criteria:** Documented formula; deterministic with fixed inputs.
- **Evidence:** `plan/evidence/phase-04-p4-t04-scarcity-fragmentation-cost.json`; golden vectors in `test_scarcity_fragmentation_scoring.py`
- **Rollback:** Zero scarcity weight.

---

### P4-T05 — Failure affinity and cooldown

- **Status:** done
- **Depends on:** P1-T12, P4-T01
- **Objective:** Failure affinity reduces re-assignment to same worker; cooldown enforced (Section 45).
- **Impacted paths:** routing service, worker failure history store
- **Acceptance criteria:** Recent failure worker deprioritized; cooldown expiry respected.
- **Evidence:** `plan/evidence/phase-04-p4-t05-failure-affinity-cooldown.json`; `database/sql/022_attempt_worker_failures.sql`
- **Rollback:** Disable affinity.

---

### P4-T06 — Queue selection ordering

- **Status:** done
- **Depends on:** P4-T01
- **Objective:** Workspace deficit RR → priority → deadline → submission time → task ID (Section 9).
- **Impacted paths:** `src/backend/edgemint/routing/service.py`, fair queue module
- **Acceptance criteria:** Ordering tests with starvation protection baseline.
- **Evidence:** `plan/evidence/phase-04-p4-t06-queue-selection-ordering.json`; `test_fair_queue_ordering.py`
- **Rollback:** N/A.

---

### P4-T07 — Deterministic worker scoring

- **Status:** done
- **Depends on:** P4-T02, P4-T03, P4-T04
- **Objective:** Combined score deterministic for same inputs (Section 38).
- **Impacted paths:** routing service
- **Acceptance criteria:** Repeated run identical assignment; tie-break uses task/worker ID.
- **Evidence:** `plan/evidence/phase-04-p4-t07-deterministic-scoring.json`; 100-iteration test
- **Rollback:** N/A.

---

### P4-T08 — Routing Decision Audit log

- **Status:** done
- **Depends on:** P4-T07
- **Objective:** Immutable audit of routing decisions with rule trace (Section 7, architecture auditability).
- **Impacted paths:** routing service, audit table/event, portal read API optional
- **Acceptance criteria:** Each assignment has audit record: candidates, scores, winner, policy hash.
- **Evidence:** `plan/evidence/phase-04-p4-t08-routing-decision-audit.json`; `database/sql/023_routing_decision_audit.sql`
- **Rollback:** Disable audit write (non-prod only).

---

### P4-T09 — Atomic reservation integration in scheduler

- **Status:** done
- **Depends on:** P2-T21, P4-T07
- **Objective:** Winner selection and reservation in one atomic transaction (Section 20).
- **Impacted paths:** assignments.py, routing service
- **Acceptance criteria:** P2-T21 scenarios pass with full scheduler stack.
- **Evidence:** `plan/evidence/phase-04-p4-t09-atomic-scheduler-integration.json`; `test_scheduler_stack.py`; `verify_production_auto_assignment_source.py`
- **Rollback:** N/A.

---

### P4-T10 — Cloud fallback decision (server-only)

- **Status:** done
- **Depends on:** P4-T09
- **Objective:** Cloud fallback only when policy permits; reason recorded (Section 52).
- **Impacted paths:** routing service, cloud fallback module
- **Acceptance criteria:** Worker never decides fallback; audit entry for each fallback.
- **Evidence:** `plan/evidence/phase-04-p4-t10-cloud-fallback.json`; `cloud_fallback.py`; `test_cloud_fallback.py`
- **Rollback:** Disable cloud path.

---

### P4-T11 — Reassignment budget enforcement

- **Status:** done
- **Depends on:** P4-T05
- **Objective:** Cap reassignments per task revision (Section 44).
- **Impacted paths:** routing service, assignment state
- **Acceptance criteria:** Exhausted budget → terminal failure, not infinite retry.
- **Evidence:** `plan/evidence/phase-04-p4-t11-reassignment-budget.json`; `test_scheduler_stack.py`
- **Rollback:** N/A.

---

### P4-T12 — Retry classification routing

- **Status:** done
- **Depends on:** P1-T12, P4-T05
- **Objective:** Route retries per Section 43: immediate/other worker, stronger worker, no retry.
- **Impacted paths:** routing service, failure classifier
- **Acceptance criteria:** Each closed code maps to retry class; tests for all classes.
- **Evidence:** `plan/evidence/phase-04-p4-t12-retry-classifier.json`; `retry_classifier.py`; `test_retry_classifier.py`
- **Rollback:** N/A.

---

### P4-T13 — Quality-aware escalation hook

- **Status:** done
- **Depends on:** P4-T12
- **Objective:** Escalate verification tier on quality failure (Section 49).
- **Impacted paths:** routing, validation service integration
- **Acceptance criteria:** Escalation increases quote tier on defined validation failures.
- **Evidence:** `plan/evidence/phase-04-p4-t13-quality-escalation.json`; `quality_escalation.py`; `test_quality_escalation.py`
- **Rollback:** Disable escalation.

---

### P4-T14 — Workspace fair queue metrics

- **Status:** done
- **Depends on:** P4-T06
- **Objective:** Expose deficit metrics for starvation monitoring (Section 9).
- **Impacted paths:** routing metrics, operations portal optional
- **Acceptance criteria:** Metric emitted per workspace; documented in ops runbook draft.
- **Evidence:** `plan/evidence/phase-04-p4-t14-fair-queue-metrics.json`; `fair_queue_metrics.py`
- **Rollback:** N/A.

---

### P4-T15 — Scheduler upgrade integration test

- **Status:** done
- **Depends on:** P4-T09, P4-T08
- **Objective:** Multi-worker multi-task assignment uses full scoring stack.
- **Impacted paths:** `tools/run_scheduler_integration_smoke.py`
- **Acceptance criteria:** Script passes with ≥3 workers and ≥10 task types.
- **Evidence:** `plan/evidence/phase-04-p4-t15-scheduler-integration-smoke.json`
- **Rollback:** N/A.

---

### P4-T16 — Phase 4 exit: closure checklist scheduling items

- **Status:** done
- **Depends on:** P4-T15
- **Objective:** Update closure checklist for resource fit, scarcity, failure affinity, model residency.
- **Impacted paths:** `plan/closure-checklist.md`
- **Acceptance criteria:** Evidenced items checked only.
- **Evidence:** `plan/evidence/phase-04-p4-t16-phase-exit.json`; updated `plan/closure-checklist.md`
- **Rollback:** N/A.
- **Rollback:** Uncheck on regression.
