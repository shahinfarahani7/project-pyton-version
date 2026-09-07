# Phase 6 — Adaptive Execution

> **Architecture ref:** Section 65 Phase 6, Sections 17, 30–35  
> **Depends on:** Phase 3–5 substantially complete  
> **Blocks:** Phase 7 consent and concurrency scenarios

## Objective

Adaptive profiles (30%/50%), device calibration in production loop, certified OCR concurrency, runtime-pair compatibility, dynamic prediction, feedback loop, consent transitions.

---

### P6-T01 — 30% default resource profile (server policy)

- **Status:** done
- **Depends on:** P2-T12, P3-T02
- **Objective:** Enforce 30% as default user-approved contribution (Sections 15, 64, 68).
- **Impacted paths:** consent policy config, scheduler budgets, worker enforcer
- **Acceptance criteria:** New workers default to 30%; documented in canonical decisions if needed.
- **Evidence:** `plan/evidence/phase-06-p6-t01-30-percent-default-policy.json`; `production/canonical-decisions.yaml`; `tests/routing/test_adaptive_execution.py`
- **Rollback:** N/A — policy value not architectural variant.

---

### P6-T02 — 50% opt-in profile (server policy)

- **Status:** done
- **Depends on:** P6-T01
- **Objective:** 50% requires explicit opt-in; server stores consent level (Section 15).
- **Impacted paths:** worker settings UI, backend consent API
- **Acceptance criteria:** Cannot reach 50% without recorded opt-in event.
- **Evidence:** `plan/evidence/phase-06-p6-t02-50-percent-opt-in-policy.json`; `database/sql/024_worker_contribution_opt_in_events.sql`; `tests/workers/test_consent_opt_in.py`
- **Rollback:** N/A.

---

### P6-T03 — Device calibration production loop

- **Status:** done
- **Depends on:** P2-T04, P3-T14
- **Objective:** Calibration profiles updated from predicted vs observed telemetry (Sections 33–34).
- **Impacted paths:** calibration service, telemetry ingestion
- **Acceptance criteria:** At least one calibration update cycle demonstrated in test.
- **Evidence:** `plan/evidence/phase-06-p6-t03-device-calibration-loop.json`; `calibration_feedback.py`; `tests/workers/test_calibration_feedback.py`
- **Rollback:** Freeze calibration updates.

---

### P6-T04 — Certified OCR concurrency (heavy + OCR)

- **Status:** done
- **Depends on:** P3-T11, P2-T18
- **Objective:** OCR may run concurrently with heavy inference only when certified (Section 30).
- **Impacted paths:** exclusive groups, OCR scheduler rules
- **Acceptance criteria:** Certification flag per device/profile; uncertified devices serialize.
- **Evidence:** `plan/evidence/phase-06-p6-t04-certified-ocr-concurrency.json`; `routing/device_certification.py`; `tests/routing/test_adaptive_execution.py`
- **Rollback:** Disable concurrent OCR globally.

---

### P6-T05 — Runtime-pair compatibility enforcement

- **Status:** done
- **Depends on:** P2-T16, P6-T04
- **Objective:** Runtime pairs (e.g. mediapipe_llm + paddle_ocr) validated for concurrent execution (Section 32).
- **Impacted paths:** compatibility matrix, scheduler
- **Acceptance criteria:** Disallowed pairs never co-scheduled on same device.
- **Evidence:** `plan/evidence/phase-06-p6-t05-runtime-pair-enforcement.json`; `runtime_compatibility.py` certified co-run exception
- **Rollback:** N/A.

---

### P6-T06 — Dynamic resource prediction

- **Status:** done
- **Depends on:** P2-T08, P6-T03
- **Objective:** Cost/reservation estimates use calibration-adjusted prediction (Section 34).
- **Impacted paths:** Task Cost Estimator, reservation ledger
- **Acceptance criteria:** Predictions change when calibration updates; bounded delta.
- **Evidence:** `plan/evidence/phase-06-p6-t06-dynamic-resource-prediction.json`; `routing/calibration.py`; `tests/routing/test_adaptive_execution.py`
- **Rollback:** Static estimates only.

---

### P6-T07 — Prediction feedback loop closure

- **Status:** done
- **Depends on:** P6-T06, P3-T14
- **Objective:** Observed usage feeds back into estimator and calibration (Section 34).
- **Impacted paths:** telemetry pipeline, calibration, estimator
- **Acceptance criteria:** Closed loop demonstrated over N assignments in test.
- **Evidence:** `plan/evidence/phase-06-p6-t07-prediction-feedback-loop.json`; `assignments.py` feedback→calibration hook
- **Rollback:** Open-loop prediction.

---

### P6-T08 — Consent increase handling (30% → 50%)

- **Status:** done
- **Depends on:** P6-T02, P3-T02
- **Objective:** Mid-session consent increase expands budgets without violating active reservations (Section 17).
- **Impacted paths:** consent API, enforcer, scheduler
- **Acceptance criteria:** P7-CHAOS-consent-30-to-50 scenario passes.
- **Evidence:** `plan/evidence/phase-06-p6-t08-consent-increase-30-to-50.json`; `consent_transitions.py`; worker `reconfigured()` enforcer
- **Rollback:** N/A.

---

### P6-T09 — Consent decrease handling (50% → 30%)

- **Status:** done
- **Depends on:** P6-T02, P3-T02
- **Objective:** Decrease applies to new work; active work completes or defers per policy (Section 17).
- **Impacted paths:** consent API, enforcer
- **Acceptance criteria:** P7-CHAOS-consent-50-to-30 scenario passes.
- **Evidence:** `plan/evidence/phase-06-p6-t09-consent-decrease-50-to-30.json`; `consent_transitions.py`
- **Rollback:** N/A.

---

### P6-T10 — Full consent revocation handling

- **Status:** done
- **Depends on:** P6-T01, P3-T02
- **Objective:** Revocation stops new assignments; active tasks wind down safely (Section 17).
- **Impacted paths:** consent API, worker enforcer, scheduler eligibility
- **Acceptance criteria:** P7-CHAOS-consent-revoke scenario passes.
- **Evidence:** `plan/evidence/phase-06-p6-t10-consent-revocation.json`; `consent_transitions.py`; `readiness.py`
- **Rollback:** N/A.

---

### P6-T11 — Adaptive concurrency certification workflow

- **Status:** done
- **Depends on:** P6-T04, P6-T05
- **Objective:** Document and implement how devices earn concurrency certification (Section 35).
- **Impacted paths:** calibration, device profile, ops runbook
- **Acceptance criteria:** Certification state visible to scheduler; revocable.
- **Evidence:** `plan/evidence/phase-06-p6-t11-concurrency-certification-workflow.json`; `docs/08-sre/runbooks/RB-022-adaptive-concurrency-certification.md`
- **Rollback:** All devices uncertified (concurrency=1).

---

### P6-T12 — Thermal transition policy

- **Status:** done
- **Depends on:** P3-T01, P6-T07
- **Objective:** Thermal events adjust adaptive concurrency and scheduling scores (Sections 35, 41).
- **Impacted paths:** worker safety controller, scheduler cooldown
- **Acceptance criteria:** P7-CHAOS-thermal-transition passes.
- **Evidence:** `plan/evidence/phase-06-p6-t12-thermal-transition-policy.json`; `exclusive_groups.py`; worker thermal OCR limit
- **Rollback:** N/A.

---

### P6-T13 — Light work during heavy inference (production)

- **Status:** done
- **Depends on:** P6-T04, P3-T11
- **Objective:** Validate Section 31 policy in production path: light/system work concurrent where safe.
- **Impacted paths:** worker execution engine, exclusive groups
- **Acceptance criteria:** Certified device runs OCR + heavy; uncertified does not.
- **Evidence:** `plan/evidence/phase-06-p6-t13-light-work-during-heavy.json`; `runtime_exclusive_group_enforcer_test.dart`
- **Rollback:** Serialize all workloads.

---

### P6-T14 — Phase 6 exit: closure checklist consent items

- **Status:** done
- **Depends on:** P6-T08, P6-T09, P6-T10, P6-T12
- **Objective:** Update closure checklist for 30%/50% and consent transitions.
- **Impacted paths:** `plan/closure-checklist.md`
- **Acceptance criteria:** Evidenced items checked.
- **Evidence:** `plan/evidence/phase-06-p6-t14-phase-6-exit-checklist.json`; `plan/closure-checklist.md` (dev evidence noted; production chaos deferred to Phase 7)
- **Rollback:** Uncheck on regression.
