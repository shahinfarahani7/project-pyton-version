# Phase 2 — Resource Foundation

> **Architecture ref:** Section 65 Phase 2, Sections 11–19, 32  
> **Depends on:** Phase 1 complete  
> **Blocks:** Phase 3–4  
> **WP cross-ref:** WP-080 (catalog), WP-090 (models) — resource vector foundation

## Objective

Device capability contracts, calibration, task resource envelopes, cost estimation, execution plans, consent policy, reservation ledger, runtime compatibility matrix, exclusive groups, and atomic reservation SQL.

---

### P2-T01 — Device Capability Contract (DSL schema)

- **Status:** done
- **Depends on:** P1-T14
- **Objective:** Define device capability contract schema in DSL (CPU, memory, storage, runtime classes).
- **Impacted paths:** `dsl/schemas/`, `docs/`
- **Acceptance criteria:** Schema validates sample fixtures; referenced in architecture Section 15.
- **Evidence:** `dsl/schemas/devicecapability.schema.json`, `dsl/catalog/device-capabilities/android-arm64-t4-reference.yaml`, `validate_dsl.py` pass.
- **Rollback:** Remove schema file.

---

### P2-T02 — Device Capability Contract (worker reporting)

- **Status:** done
- **Depends on:** P2-T01
- **Objective:** Worker reports capabilities matching contract on heartbeat/register.
- **Impacted paths:** `src/apps/worker/lib/`, `src/backend/edgemint/services/worker_registry.py`
- **Acceptance criteria:** Report payload validates against schema; stored server-side.
- **Evidence:** plan/evidence/phase-02-p2-t02-device-capability-reporting.json + validate_sql + pytest(5)
- **Rollback:** Revert reporting fields.

---

### P2-T03 — Worker Calibration Profile (schema)

- **Status:** done
- **Depends on:** P2-T01
- **Objective:** Calibration profile schema per Section 33 (observed throughput, thermal hints).
- **Impacted paths:** `dsl/schemas/`, `database/sql/`
- **Acceptance criteria:** Schema + migration stub or table design documented.
- **Evidence:** dsl/schemas/workercalibrationprofile.schema.json + validate_dsl pass
- **Rollback:** N/A.

---

### P2-T04 — Worker Calibration Profile (persistence + API)

- **Status:** done
- **Depends on:** P2-T03
- **Objective:** Server stores and serves calibration profiles per worker/device.
- **Impacted paths:** `src/backend/edgemint/routing/`, worker telemetry ingestion
- **Acceptance criteria:** CRUD or upsert path tested; feeds Phase 6 calibration.
- **Evidence:** plan/evidence/phase-02-p2-t04-calibration-persistence.json
- **Rollback:** Drop table migration.

---

### P2-T05 — Task Resource Envelope (DSL)

- **Status:** done
- **Depends on:** P2-T01
- **Objective:** Per-task-type resource envelope schema (Section 12).
- **Impacted paths:** `dsl/schemas/`, `src/shared/task-types/`
- **Acceptance criteria:** Envelope attached to catalog entries in DSL; validator passes.
- **Evidence:** dsl/schemas/taskresourceenvelope.schema.json + validate_dsl
- **Rollback:** Revert schema.

---

### P2-T06 — Task Resource Envelope (catalog binding)

- **Status:** done
- **Depends on:** P2-T05, P0-T06
- **Objective:** Bind envelopes to all 56 task types (initial defaults acceptable if documented).
- **Impacted paths:** `src/shared/task-types/catalog.json`, task type catalog backend
- **Acceptance criteria:** 56/56 tasks have envelope reference or explicit waiver in audit-matrix.
- **Evidence:** plan/evidence/phase-02-resource-envelope-bindings.json (56/56)
- **Rollback:** Revert catalog bindings.

---

### P2-T07 — Task Cost Estimator (interface)

- **Status:** done
- **Depends on:** P2-T05
- **Objective:** Input-aware cost estimation interface (Section 13).
- **Impacted paths:** `src/backend/edgemint/routing/service.py`, pricing/quote modules
- **Acceptance criteria:** Interface documented; deterministic quote inputs listed.
- **Evidence:** routing/cost_estimator.py + tests/routing/test_cost_estimator.py (2 passed)
- **Rollback:** Revert interface.

---

### P2-T08 — Task Cost Estimator (implementation)

- **Status:** done
- **Depends on:** P2-T07
- **Objective:** Estimator uses envelope + input size + verification tier modifiers.
- **Impacted paths:** `src/backend/edgemint/routing/`, `tests/vectors/pricing-vectors.jsonl`
- **Acceptance criteria:** Pricing vectors pass; no floating point for money (canonical decision).
- **Evidence:** plan/evidence/phase-02-p2-t08-cost-estimator.json + pytest(10)
- **Rollback:** Feature flag estimator.

---

### P2-T09 — Execution Plan (schema)

- **Status:** done
- **Depends on:** P2-T05
- **Objective:** Execution plan schema for multi-stage tasks (Section 14).
- **Impacted paths:** `dsl/schemas/`
- **Acceptance criteria:** Plan resolves from task type + input; schema validates examples.
- **Evidence:** dsl/schemas/taskexecutionplan.schema.json + 3 execution-plan fixtures + validate_dsl
- **Rollback:** N/A.

---

### P2-T10 — Execution Plan (resolver)

- **Status:** done
- **Depends on:** P2-T09
- **Objective:** ExecutionPlanResolver in control plane pipeline (Section 7).
- **Impacted paths:** `src/backend/edgemint/routing/service.py`
- **Acceptance criteria:** Long summarize task yields map/reduce plan stub or full plan per architecture.
- **Evidence:** routing/execution_plan_resolver.py + RouterService + pytest(3)
- **Rollback:** Revert resolver.

---

### P2-T11 — User Consent Policy (schema)

- **Status:** done
- **Depends on:** P2-T01
- **Objective:** Consent policy model: 30% default, 50% opt-in (Sections 15, 17, 64).
- **Impacted paths:** `dsl/`, worker settings UI, backend policy store
- **Acceptance criteria:** Policy values server-authoritative; not worker-decided.
- **Evidence:** `dsl/schemas/userresourcepolicy.schema.json`, `dsl/policies/consent/production-resource-policy-v1.yaml`, `src/backend/edgemint/workers/resource_policy.py`, `GET /policy/resource-contribution` in `contracts/openapi/edgemint-worker-api.yaml`, `src/backend/tests/workers/test_resource_policy.py`, `plan/evidence/phase-02-p2-t11-user-resource-policy.json`
- **Rollback:** N/A.

---

### P2-T12 — User Consent Policy (enforcement hooks)

- **Status:** done
- **Depends on:** P2-T11
- **Objective:** Scheduler reads consent level for resource budget caps.
- **Impacted paths:** `src/backend/edgemint/routing/service.py`, worker consent reporting
- **Acceptance criteria:** 30% and 50% map to distinct budget multipliers in config.
- **Evidence:** `src/backend/edgemint/routing/resource_budget.py`, `database/sql/017_worker_contribution_mode.sql`, `RouterService.contribution_budget_multiplier_bps_for_worker`, `src/backend/tests/routing/test_resource_budget.py`, `plan/evidence/phase-02-p2-t12-consent-enforcement.json`
- **Rollback:** Revert enforcement.

---

### P2-T13 — Reservation Ledger (SQL)

- **Status:** done
- **Depends on:** P1-T09
- **Objective:** Resource reservation ledger tables (Section 19).
- **Impacted paths:** `database/sql/`, new migration file
- **Acceptance criteria:** Ledger supports reserve, commit, release per resource class; validate_sql pass.
- **Evidence:** `database/sql/018_worker_resource_reservations.sql`, `tests/database/test_worker_resource_reservations_sql.py`, `plan/evidence/phase-02-p2-t13-reservation-ledger-sql.json`
- **Rollback:** Down migration.

---

### P2-T14 — Reservation Ledger (service API)

- **Status:** done
- **Depends on:** P2-T13
- **Objective:** API for atomic reserve/release used by assignment transaction.
- **Impacted paths:** `src/backend/edgemint/routing/`, `src/backend/edgemint/workers/assignments.py`
- **Acceptance criteria:** Double-release impossible; idempotent release.
- **Evidence:** `src/backend/edgemint/routing/resource_reservations.py`, hooks in `routing/service.py` + `workers/assignments.py`, `src/backend/tests/routing/test_resource_reservations.py`, `plan/evidence/phase-02-p2-t14-reservation-ledger-service.json`
- **Rollback:** Disable ledger feature flag (`EDGEMINT_WORKER_RESOURCE_RESERVATIONS_ENABLED=false`).

---

### P2-T15 — Runtime Compatibility Matrix (DSL)

- **Status:** done
- **Depends on:** P2-T05
- **Objective:** Matrix of runtime class pairs and task compatibility (Section 32).
- **Impacted paths:** `dsl/schemas/`, Section 59 runtime classes
- **Acceptance criteria:** Matrix covers paddle_ocr, mediapipe_llm, image_classifier, etc.
- **Evidence:** `dsl/schemas/runtimecompatibilityprofile.schema.json`, `dsl/catalog/runtime-compatibility/production-v1.yaml`, `tools/validate_dsl.py` invariants, `src/backend/tests/dev/test_runtime_compatibility_dsl.py`, `plan/evidence/phase-02-p2-t15-runtime-compatibility-matrix.json`
- **Rollback:** Revert matrix file.

---

### P2-T16 — Runtime Compatibility Matrix (scheduler filter)

- **Status:** done
- **Depends on:** P2-T15, P2-T02
- **Objective:** Hard filter excludes incompatible worker+task pairs.
- **Impacted paths:** `src/backend/edgemint/routing/service.py`
- **Acceptance criteria:** Test: incompatible runtime never assigned.
- **Evidence:** `src/backend/edgemint/routing/runtime_compatibility.py`, `routing/engine.py` eligibility hook, `src/backend/tests/routing/test_runtime_compatibility_filter.py`, `plan/evidence/phase-02-p2-t16-runtime-compatibility-filter.json`
- **Rollback:** Revert filter.

---

### P2-T17 — Exclusive Groups (definition)

- **Status:** done
- **Depends on:** P2-T05
- **Objective:** Define exclusive resource groups (e.g. one heavy LLM) per Section 29.
- **Impacted paths:** `dsl/`, routing config
- **Acceptance criteria:** Groups documented; OCR + heavy LLM exclusivity rules stated.
- **Evidence:** `dsl/schemas/exclusivegrouppolicy.schema.json`, `dsl/policies/scheduling/production-exclusive-groups-v1.yaml`, `tools/validate_dsl.py` invariants, `src/backend/tests/dev/test_exclusive_group_policy_dsl.py`, `plan/evidence/phase-02-p2-t17-exclusive-groups.json`
- **Rollback:** N/A.

---

### P2-T18 — Exclusive Groups (enforcement)

- **Status:** done
- **Depends on:** P2-T17, P2-T14
- **Objective:** Ledger enforces exclusive group caps per device.
- **Impacted paths:** reservation ledger service, scheduler
- **Acceptance criteria:** Second heavy task blocked when group saturated.
- **Evidence:** `src/backend/edgemint/routing/exclusive_groups.py`, `ResourceReservationService.assert_exclusive_group_available`, `src/backend/tests/routing/test_exclusive_group_enforcement.py`, `plan/evidence/phase-02-p2-t18-exclusive-group-enforcement.json`
- **Rollback:** Revert enforcement.

---

### P2-T19 — Per-resource-class budgets (CPU/memory/storage)

- **Status:** done
- **Depends on:** P2-T12, P2-T14
- **Objective:** Budgets tracked per resource class (Sections 16, 18).
- **Impacted paths:** routing, worker enforcer hooks (Phase 3 prep)
- **Acceptance criteria:** Three resource classes independently reserved.
- **Evidence:** `src/backend/edgemint/routing/resource_budget.py`, `ResourceReservationService.assert_per_class_resource_budget_available`, `src/backend/tests/routing/test_per_class_resource_budget.py`, `plan/evidence/phase-02-p2-t19-per-class-resource-budgets.json`
- **Rollback:** N/A.

---

### P2-T20 — Atomic Reservation SQL (transaction design)

- **Status:** done
- **Depends on:** P2-T13, P2-T14
- **Objective:** Single transaction: score winner → reserve → assign → lease → outbox (Section 20).
- **Impacted paths:** `database/sql/`, `src/backend/edgemint/routing/atomic_assignment.py`, `src/backend/edgemint/routing/service.py`
- **Acceptance criteria:** Transaction boundary documented; failure rolls back reservation.
- **Evidence:** `database/sql/019_atomic_assignment_transaction.sql`, `src/backend/edgemint/routing/atomic_assignment.py`, `src/backend/tests/routing/test_atomic_assignment_transaction.py`, `tests/database/test_atomic_assignment_transaction_sql.py`, `plan/evidence/phase-02-p2-t20-atomic-assignment-transaction.json`
- **Rollback:** Revert transaction wrapper.

---

### P2-T21 — Atomic Reservation SQL (production verification)

- **Status:** done
- **Depends on:** P2-T20, P1-T13
- **Objective:** Verify atomic path on production code path, not dev-only fixtures.
- **Impacted paths:** `tools/verify_production_auto_assignment_source.py`
- **Acceptance criteria:** Verify script passes; classified IMPLEMENTED_PRODUCTION in audit-matrix.
- **Evidence:** `tools/verify_production_auto_assignment_source.py` exit 0, `plan/evidence/phase-02-p2-t21-atomic-production-verify.json`
- **Rollback:** N/A.

---

### P2-T22 — Phase 2 exit: closure checklist resource items

- **Status:** done
- **Depends on:** P2-T21
- **Objective:** Update [closure-checklist.md](../closure-checklist.md) for reservation, envelope, estimator, execution plan items.
- **Impacted paths:** `plan/closure-checklist.md`
- **Acceptance criteria:** Only evidenced items checked.
- **Evidence:** `plan/closure-checklist.md`, `plan/evidence/phase-02-p2-t22-phase-exit.json`
- **Rollback:** Uncheck on regression.
