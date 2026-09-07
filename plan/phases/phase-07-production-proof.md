# Phase 7 — Production Proof

> **Architecture ref:** Section 65 Phase 7, Section 69 (v1-plan scope; superseded by v2 §70)  
> **Depends on:** Phases 0–6 complete  
> **Blocks:** v1-plan closure (complete); v2 full closure → Phase 8

## Objective

Prove production readiness through load, chaos, and exactly-once scenarios. Each chaos task produces an evidence artifact under `artifacts/` or `evidence/`.

---

## Meta tasks

### P7-T01 — Rollout and rollback procedures

- **Status:** done
- **Depends on:** P6-T14, P5-GAP-08
- **Objective:** Document and exercise rollout/rollback for scheduler, worker, and backend (Section 69).
- **Impacted paths:** `docs/`, deploy scripts, Helm/terraform if applicable
- **Acceptance criteria:** Dry-run rollback executed in staging; runbook reviewed.
- **Evidence:** `plan/evidence/phase-07-p7-t01-rollout-rollback-drill.json`; `docs/08-sre/drills/DR-001-architecture-v1-rollback-dry-run.md`; `docs/08-sre/runbooks/RB-025-release-rollback.md`
- **Rollback:** N/A.

---

### P7-T02 — Phase 7 exit: architecture v1 closure sign-off

- **Status:** done
- **Depends on:** All P7-CHAOS-* tasks, P7-T01
- **Objective:** Final review of Section 69 checklist; architecture v1 implementation closure decision.
- **Impacted paths:** `plan/closure-checklist.md`, `plan/audit-matrix.md`, `plan/TODO.md`
- **Acceptance criteria:** All Section 69 items checked with evidence or explicit deferred v2 item.
- **Evidence:** `plan/evidence/phase-07-p7-t02-architecture-v1-closure-signoff.json` (26/26 chaos passed, 2026-09-02)
- **Rollback:** Reopen phases as needed.

---

## Production proof scenarios

Each scenario follows this template:

- **Pass criteria:** Scenario completes without invariant violation; evidence artifact saved.
- **Evidence:** JSON/log under `artifacts/` or `evidence/actual/`.
- **Depends on:** Relevant phase completion (noted per task).

---

### P7-CHAOS-20-workers — 20-worker load test

- **Status:** done
- **Depends on:** P4-T15, P5-GAP-08
- **Objective:** Sustained load with 20 workers accepting assignments.
- **Acceptance criteria:** Error rate under defined SLO; no reservation leaks.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-20-workers.json`; `tools/run_56_task_protocol_load.py`

---

### P7-CHAOS-56-task-catalog — Full catalog execution sample

- **Status:** done
- **Depends on:** P5-GAP-08
- **Objective:** Execute representative job for each of 56 task types (or documented waiver).
- **Acceptance criteria:** 56/56 represented in execution log.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-56-task-catalog.json`

---

### P7-CHAOS-multi-assignment — Multi-assignment per worker

- **Status:** done
- **Depends on:** P4-T09, P6-T04
- **Objective:** Workers hold multiple assignments where policy allows (light + heavy rules).
- **Acceptance criteria:** No fence violations; reservations correct.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-multi-assignment.json`

---

### P7-CHAOS-resource-exhaustion — Resource exhaustion

- **Status:** done
- **Depends on:** P2-T21
- **Objective:** Cluster exhausts capacity; scheduler backpressures fairly.
- **Acceptance criteria:** No over-commit; queue ordering preserved.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-resource-exhaustion.json`

---

### P7-CHAOS-worker-disconnect — Worker disconnect mid-assignment

- **Status:** done
- **Depends on:** P1-T13
- **Objective:** Worker disconnect triggers reassignment per policy.
- **Acceptance criteria:** Assignment reaches terminal state; reservation released.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-worker-disconnect.json`

---

### P7-CHAOS-lease-expiry — Lease expiry

- **Status:** done
- **Depends on:** P1-T06, P1-T07
- **Objective:** Expired lease rejects progress/result writes.
- **Acceptance criteria:** Stale worker writes fail; reassignment possible.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-lease-expiry.json`

---

### P7-CHAOS-stale-result — Stale result submission

- **Status:** done
- **Depends on:** P1-T08
- **Objective:** Result from superseded assignment rejected.
- **Acceptance criteria:** Closed failure code; no reward.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-stale-result.json`

---

### P7-CHAOS-runtime-crash — Runtime crash during execution

- **Status:** done
- **Depends on:** P3-T13
- **Objective:** Worker runtime crash produces failure evidence and server retry path.
- **Acceptance criteria:** Failure evidence ingested; retry class applied.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-runtime-crash.json`

---

### P7-CHAOS-oom — OOM / memory pressure

- **Status:** done
- **Depends on:** P3-T01, P3-T02
- **Objective:** OOM risk triggers safety deferral/stop without local retry.
- **Acceptance criteria:** Server decides next action; worker does not self-reassign.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-oom.json`

---

### P7-CHAOS-thermal-failure — Thermal failure

- **Status:** done
- **Depends on:** P3-T01
- **Objective:** Thermal critical stops execution safely.
- **Acceptance criteria:** Failure evidence code for thermal; cooldown applied.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-thermal-failure.json`

---

### P7-CHAOS-retry-exhaustion — Retry exhaustion

- **Status:** done
- **Depends on:** P4-T11
- **Objective:** Task hits reassignment budget limit → terminal failure.
- **Acceptance criteria:** No infinite retry loop.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-retry-exhaustion.json`

---

### P7-CHAOS-cloud-fallback — Cloud fallback

- **Status:** done
- **Depends on:** P4-T10
- **Objective:** Edge failure triggers server-authorized cloud fallback with audit.
- **Acceptance criteria:** Fallback reason + cost increment recorded.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-cloud-fallback.json`

---

### P7-CHAOS-reward-exactly-once — Reward exactly-once

- **Status:** done
- **Depends on:** P5-CROSS-01, P1-T08
- **Objective:** Duplicate completion does not double-reward (Section 50–51).
- **Acceptance criteria:** Idempotent reward ledger proof.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-reward-exactly-once.json`

---

### P7-CHAOS-long-context-summarize — Long-context summarize

- **Status:** done
- **Depends on:** P3-T07
- **Objective:** Long input summarize via map/reduce completes successfully.
- **Acceptance criteria:** Output quality baseline met; checkpoints optional.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-long-context-summarize.json`

---

### P7-CHAOS-chunk-resume — Chunk resume after crash

- **Status:** done
- **Depends on:** P3-T08
- **Objective:** Resume from chunk checkpoint after simulated crash.
- **Acceptance criteria:** Fence-aware resume; no duplicate chunk processing.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-chunk-resume.json`

---

### P7-CHAOS-recursive-reduce — Recursive reduce depth

- **Status:** done
- **Depends on:** P3-T07
- **Objective:** Multi-level hierarchical reduce for very long input.
- **Acceptance criteria:** Completes within resource envelope; correct aggregation.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-recursive-reduce.json`

---

### P7-CHAOS-model-corruption — Model corruption detection

- **Status:** done
- **Depends on:** P3-T16
- **Objective:** Corrupted model file rejected before execution.
- **Acceptance criteria:** Failure evidence; no partial reward.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-model-corruption.json`

---

### P7-CHAOS-model-update — Model update during residency

- **Status:** done
- **Depends on:** P3-T03
- **Objective:** Model update while resident handled per lifecycle policy (Section 53).
- **Acceptance criteria:** Active assignment not broken; update queued or safe swap.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-model-update.json`

---

### P7-CHAOS-storage-pressure — Storage pressure

- **Status:** done
- **Depends on:** P3-T17
- **Objective:** Device storage pressure triggers eviction policy (Section 54).
- **Acceptance criteria:** Active assignment protected; eviction auditable.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-storage-pressure.json`

---

### P7-CHAOS-consent-30-to-50 — Consent 30% to 50%

- **Status:** done
- **Depends on:** P6-T08
- **Objective:** Live consent increase during operation.
- **Acceptance criteria:** Budget expands per policy; no reservation corruption.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-consent-30-to-50.json`

---

### P7-CHAOS-consent-50-to-30 — Consent 50% to 30%

- **Status:** done
- **Depends on:** P6-T09
- **Objective:** Live consent decrease during operation.
- **Acceptance criteria:** New work capped at 30%; active work policy honored.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-consent-50-to-30.json`

---

### P7-CHAOS-consent-revoke — Full consent revocation

- **Status:** done
- **Depends on:** P6-T10
- **Objective:** User revokes compute contribution consent.
- **Acceptance criteria:** Worker ineligible for new assignments; graceful wind-down.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-consent-revoke.json`

---

### P7-CHAOS-thermal-transition — Thermal state transition

- **Status:** done
- **Depends on:** P6-T12
- **Objective:** Thermal state change affects concurrency/scoring mid-flight.
- **Acceptance criteria:** Adaptive policy responds; no worker-side reschedule.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-thermal-transition.json`

---

### P7-CHAOS-websocket-replay — WebSocket replay

- **Status:** done
- **Depends on:** P1-T05
- **Objective:** Replay after reconnect does not duplicate execution.
- **Acceptance criteria:** Idempotent delivery + fence semantics.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-websocket-replay.json`

---

### P7-CHAOS-stale-fence-writes — Stale fence writes

- **Status:** done
- **Depends on:** P1-T08
- **Objective:** All stale fence write paths rejected (progress, checkpoint, result).
- **Acceptance criteria:** 100% rejection in negative test suite.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-stale-fence-writes.json`

---

### P7-CHAOS-duplicate-delivery — Duplicate assignment delivery

- **Status:** done
- **Depends on:** P1-T05, P1-T10
- **Objective:** Duplicate WS delivery does not create double execution.
- **Acceptance criteria:** Single execution per assignment ID + fence.
- **Evidence:** `plan/evidence/phase-07-p7-chaos-duplicate-delivery.json`
