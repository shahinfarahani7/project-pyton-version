# Phase 3 — Worker Runtime Foundation

> **Architecture ref:** Section 65 Phase 3, Sections 8, 24–28, 18, 34  
> **Depends on:** Phase 2 complete  
> **Blocks:** Phase 4–6

## Objective

Worker-side runtime components: safety controller, resource enforcer, model/session lifecycle, context budget, chunking/reduce, checkpoints, telemetry feedback — without local scheduling authority.

---

### P3-T01 — RuntimeSafetyController

- **Status:** done
- **Depends on:** P2-T22
- **Objective:** Implement RuntimeSafetyController for OOM/thermal/OS pressure deferral (Sections 18, 41).
- **Impacted paths:** `src/apps/worker/lib/runtime/runtime_safety_controller.dart`, `assignment_coordinator.dart`
- **Acceptance criteria:** Worker may defer/stop for safety; does NOT reschedule or reassign locally.
- **Evidence:** `src/apps/worker/test/runtime/runtime_safety_controller_test.dart`, `plan/evidence/phase-03-p3-t01-runtime-safety-controller.json`
- **Rollback:** Remove module; fallback to basic cancel.

---

### P3-T02 — WorkerResourceEnforcer

- **Status:** done
- **Depends on:** P2-T19, P3-T01
- **Objective:** Enforce consent and per-class budgets locally (Section 18).
- **Impacted paths:** `src/apps/worker/lib/runtime/worker_resource_enforcer.dart`, `worker_resource_budget.dart`, `assignment_coordinator.dart`
- **Acceptance criteria:** 30%/50% caps enforced; violation reports telemetry, not local retry.
- **Evidence:** `src/apps/worker/test/runtime/worker_resource_enforcer_test.dart`, `plan/evidence/phase-03-p3-t02-worker-resource-enforcer.json`
- **Rollback:** Disable enforcer.

---

### P3-T03 — ModelRuntimeManager (lifecycle)

- **Status:** done
- **Depends on:** P0-T03, P3-T01
- **Objective:** Manage model resident state and short-lived sessions (Section 24).
- **Impacted paths:** `model_runtime_manager.dart`, `gemma_model_runtime_manager.dart`, `gemma_inference_adapter.dart`
- **Acceptance criteria:** One primary heavy model policy; session fresh per inference stage.
- **Evidence:** `src/apps/worker/test/runtime/model_runtime_manager_test.dart`, `plan/evidence/phase-03-p3-t03-model-runtime-manager.json`
- **Rollback:** Revert to direct adapter calls.

---

### P3-T04 — ContextBudgetManager

- **Status:** done
- **Depends on:** P0-T05, P3-T03
- **Objective:** Guard context/maxTokens before native runtime (Sections 25, 71).
- **Impacted paths:** `context_budget_manager.dart`, `qwen_task_processor.dart`
- **Acceptance criteria:** Oversized input triggers chunk path, not native OOM.
- **Evidence:** `test/inference/llm/context_budget_manager_test.dart`, `plan/evidence/phase-03-p3-t04-context-budget-manager.json`
- **Rollback:** Hard reject oversized input (interim).

---

### P3-T05 — Session lifecycle integration

- **Status:** done
- **Depends on:** P3-T03
- **Objective:** Wire session open → infer → close across ExecutionPlanRunner.
- **Impacted paths:** `execution_plan_runner.dart`, `task_execution_engine.dart`
- **Acceptance criteria:** No session leak across assignments; fence checked on entry.
- **Evidence:** `test/runtime/execution_plan_runner_test.dart`, `test/tasks/task_execution_engine_test.dart`, `plan/evidence/phase-03-p3-t05-session-lifecycle-integration.json`
- **Rollback:** Revert session wrapper.

---

### P3-T06 — Semantic ChunkEngine

- **Status:** done
- **Depends on:** P3-T04
- **Objective:** Chunk long inputs per Section 27 rules.
- **Impacted paths:** `semantic_chunk_engine.dart`, `qwen_task_processor.dart`
- **Acceptance criteria:** Deterministic chunk boundaries; metadata for map stage.
- **Evidence:** `test/inference/llm/semantic_chunk_engine_test.dart`, `fixtures/semantic_chunk_golden.dart`, `plan/evidence/phase-03-p3-t06-semantic-chunk-engine.json`
- **Rollback:** Disable chunking for long tasks (dev only).

---

### P3-T07 — Hierarchical Reduce

- **Status:** done
- **Depends on:** P3-T06
- **Objective:** Map/reduce summarization pipeline (Section 26).
- **Impacted paths:** `hierarchical_summarize_pipeline.dart`, `qwen_task_processor.dart`, `document_handlers.dart`
- **Acceptance criteria:** Long summarize task completes via multi-chunk reduce; quality baseline test.
- **Evidence:** `test/inference/llm/hierarchical_summarize_pipeline_test.dart`, `plan/evidence/phase-03-p3-t07-hierarchical-reduce.json`
- **Rollback:** Single-pass summarize only (non-prod).

---

### P3-T08 — CheckpointManager

- **Status:** done
- **Depends on:** P3-T06, P1-T08
- **Objective:** Chunk checkpoints fence-aware (Sections 28, 46).
- **Impacted paths:** worker checkpoint storage, backend checkpoint API if any
- **Acceptance criteria:** Resume from checkpoint respects fence; stale checkpoint rejected server-side.
- **Evidence:** `src/apps/worker/lib/runtime/checkpoint_manager.dart`, `src/apps/worker/test/runtime/checkpoint_manager_test.dart`, `plan/evidence/phase-03-p3-t08-checkpoint-manager.json`
- **Rollback:** Disable checkpoints.

---

### P3-T09 — ExecutionPlanRunner shell

- **Status:** done
- **Depends on:** P2-T10, P3-T01
- **Objective:** Orchestrate plan stages through safety, enforcer, runtimes (Section 8).
- **Impacted paths:** `src/apps/worker/lib/tasks/task_execution_engine.dart`
- **Acceptance criteria:** Plan stages execute in order; progress events emitted.
- **Evidence:** `src/apps/worker/test/runtime/execution_plan_runner_test.dart`, `plan/evidence/phase-03-p3-t09-execution-plan-runner.json`
- **Rollback:** Single-stage execution only.

---

### P3-T10 — Progress and checkpoint events

- **Status:** done
- **Depends on:** P3-T08, P3-T09
- **Objective:** Stream progress/checkpoint to server with fence token.
- **Impacted paths:** worker API client, backend assignment handlers
- **Acceptance criteria:** Events in CloudEvents/async contract; ordering documented.
- **Evidence:** `src/backend/tests/workers/test_assignment_progress_checkpoint.py`, `src/apps/worker/test/runtime/assignment_event_reporter_test.dart`, `plan/evidence/phase-03-p3-t10-progress-checkpoint-events.json`
- **Rollback:** Batch progress only.

---

### P3-T11 — OCR runtime integration under enforcer

- **Status:** done
- **Depends on:** P3-T02, P3-T09
- **Objective:** OCR runs as light workload concurrent with heavy policy (Section 30 prep).
- **Impacted paths:** OCR handlers, paddle OCR path
- **Acceptance criteria:** OCR respects exclusive group when heavy active.
- **Evidence:** `src/apps/worker/test/runtime/runtime_exclusive_group_enforcer_test.dart`, `plan/evidence/phase-03-p3-t11-ocr-runtime-enforcer.json`
- **Rollback:** Serialize all work.

---

### P3-T12 — Vision runtime integration

- **Status:** done
- **Depends on:** P3-T09
- **Objective:** Vision handlers use vision runtime classes per Section 59.
- **Impacted paths:** `src/apps/worker/lib/tasks/handlers/vision_handlers.dart`, `vision_litert_adapter.dart`
- **Acceptance criteria:** Classify vs segment vs VLM paths distinct.
- **Evidence:** `src/apps/worker/test/runtime/vision_runtime_routing_test.dart`, `plan/evidence/phase-03-p3-t12-vision-runtime-integration.json`
- **Rollback:** N/A.

---

### P3-T13 — Failure evidence submission

- **Status:** done
- **Depends on:** P1-T12, P3-T01
- **Objective:** Worker submits structured failure evidence (Section 42).
- **Impacted paths:** worker failure reporting, backend ingestion
- **Acceptance criteria:** Closed codes only; thermal/OOM/runtime crash mapped.
- **Evidence:** `src/backend/tests/workers/test_assignment_fail.py`, `src/apps/worker/test/runtime/failure_evidence_mapper_test.dart`, `plan/evidence/phase-03-p3-t13-failure-evidence.json`
- **Rollback:** N/A.

---

### P3-T14 — Predicted vs observed telemetry

- **Status:** done
- **Depends on:** P3-T09, P2-T04
- **Objective:** Report predicted vs observed resource usage for feedback loop (Section 34).
- **Impacted paths:** worker telemetry, backend calibration ingestion
- **Acceptance criteria:** Payload schema defined; stored for Phase 6 feedback.
- **Evidence:** `src/backend/tests/workers/test_execution_cost_feedback.py`, `src/apps/worker/test/telemetry/execution_cost_feedback_test.dart`, `plan/evidence/phase-03-p3-t14-predicted-observed-telemetry.json`
- **Rollback:** Disable telemetry fields.

---

### P3-T15 — Assignment receiver hardening

- **Status:** done
- **Depends on:** P1-T04, P3-T09
- **Objective:** Receiver validates contract, fence, consent before ExecutionPlanRunner (Section 8 diagram).
- **Impacted paths:** worker assignment coordinator
- **Acceptance criteria:** Invalid assignment rejected locally with evidence; no execution.
- **Evidence:** `src/apps/worker/test/runtime/assignment_receiver_test.dart`, `src/apps/worker/test/runtime/assignment_coordinator_test.dart`, `plan/evidence/phase-03-p3-t15-assignment-receiver-hardening.json`
- **Rollback:** N/A.

---

### P3-T16 — Model download and verify hook

- **Status:** done
- **Depends on:** P3-T03
- **Objective:** Signed model verify before execute (Section 53).
- **Impacted paths:** worker model download, SHA/signature verify
- **Acceptance criteria:** Unsigned model rejected; corruption triggers failure evidence.
- **Evidence:** `src/apps/worker/test/runtime/model_artifact_verifier_test.dart`, `plan/evidence/phase-03-p3-t16-model-download-verify-hook.json`
- **Rollback:** N/A.

---

### P3-T17 — Storage pressure handling

- **Status:** done
- **Depends on:** P3-T03, P3-T02
- **Objective:** Local storage policy under pressure (Sections 16, 54).
- **Impacted paths:** worker model storage, eviction policy
- **Acceptance criteria:** Eviction does not break active fence assignment.
- **Evidence:** `src/apps/worker/test/runtime/storage_pressure_manager_test.dart`, `plan/evidence/phase-03-p3-t17-storage-pressure-handling.json`
- **Rollback:** Manual cleanup only.

---

### P3-T18 — Worker telemetry heartbeat alignment

- **Status:** done
- **Depends on:** P2-T02, P3-T14
- **Objective:** Heartbeat carries capability, consent, calibration, active reservations view (Section 39).
- **Impacted paths:** worker heartbeat, worker_registry
- **Acceptance criteria:** Server reconciliation possible (Phase 2 §40 prep).
- **Evidence:** `plan/evidence/phase-03-p3-t18-heartbeat-telemetry.json`; `src/backend/tests/workers/test_heartbeat_telemetry.py`; `src/apps/worker/test/runtime/worker_heartbeat_telemetry_test.dart`
- **Rollback:** N/A.

---

### P3-T19 — Phase 3 integration smoke

- **Status:** done
- **Depends on:** P3-T09, P3-T13, P3-T15
- **Objective:** End-to-end worker executes assignment through ExecutionPlanRunner on device/emulator.
- **Impacted paths:** dev stack, worker app
- **Acceptance criteria:** At least one OCR + one Qwen task complete with new runtime shell.
- **Evidence:** `plan/evidence/phase-03-p3-t19-integration-smoke.json`; `src/apps/worker/test/integration/phase_03_runtime_smoke_test.dart`
- **Rollback:** N/A.

---

### P3-T20 — Forbidden local scheduler audit (Phase 3 gate)

- **Status:** done
- **Depends on:** P3-T19
- **Objective:** Re-run Section 2.3 forbidden component grep; confirm no local scheduling authority introduced.
- **Impacted paths:** `src/apps/worker/lib/`
- **Acceptance criteria:** audit-matrix forbidden table clean; sign-off in Phase 3 notes.
- **Evidence:** `plan/evidence/phase-03-p3-t20-forbidden-scheduler-audit.json`
- **Rollback:** Remove violating code.

---

### P3-T21 — Phase 3 exit: closure checklist worker items

- **Status:** done
- **Depends on:** P3-T20
- **Objective:** Update closure checklist for worker safety, checkpoint, Qwen lifecycle items.
- **Impacted paths:** `plan/closure-checklist.md`
- **Acceptance criteria:** Evidenced items only.
- **Evidence:** `plan/evidence/phase-03-p3-t21-phase-exit.json`; `plan/closure-checklist.md` worker runtime section
- **Rollback:** Uncheck on regression.
