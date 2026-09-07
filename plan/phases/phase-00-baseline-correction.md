# Phase 0 — Baseline Correction

> **Architecture ref:** Section 65 Phase 0, Sections 4, 56, 66  
> **Depends on:** None (entry phase)  
> **Blocks:** Phase 1+  
> **WP cross-ref:** WP-090 (models), WP-080 (catalog) — see audit-matrix.md

## Objective

Establish an evidence-based baseline: verify Qwen runtime, model lifecycle, catalog inventory, production vs dev paths, and worker scheduling authority before structural changes.

---

### P0-T01 — Audit classification for Phase 0 scope

- **Status:** done
- **Depends on:** —
- **Objective:** Apply Section 66 classification to every Phase 0 feature area; seed [audit-matrix.md](../audit-matrix.md).
- **Impacted paths:** `plan/audit-matrix.md`
- **Acceptance criteria:** Each Phase 0 row has a status (`IMPLEMENTED_*` or `MISSING`) and notes citing file paths or test names.
- **Evidence:** plan/audit-matrix.md (Phase 0 inventory seeded)
- **Rollback:** Revert audit-matrix rows to scaffold.

---

### P0-T02 — Verify Qwen2.5 0.5B runtime path

- **Status:** done
- **Depends on:** P0-T01
- **Objective:** Confirm on-device LLM baseline (Section 4) uses Qwen2.5 0.5B through approved adapter path.
- **Impacted paths:** `src/apps/worker/lib/runtime/gemma_inference_adapter.dart`, `src/apps/worker/lib/inference/llm/qwen_task_processor.dart`, `src/backend/edgemint/dev/model_artifact_proxy.py`
- **Acceptance criteria:** Documented call chain from assignment → runtime → model artifact; dev smoke test path identified.
- **Evidence:** WorkerModelCatalog + GemmaLiteRtInferenceAdapter + tools/run_qwen_real_inference.py
- **Rollback:** N/A (audit only).

---

### P0-T03 — Verify model lifecycle

- **Status:** done
- **Depends on:** P0-T02
- **Objective:** Trace download → signature verify → resident model → short-lived session (Section 24).
- **Impacted paths:** `src/apps/worker/lib/models/worker_model_catalog.dart`, `src/apps/worker/lib/runtime/gemma_inference_adapter.dart`, worker UI model tab
- **Acceptance criteria:** Lifecycle diagram in audit notes; gaps listed for ModelRuntimeManager (Phase 3).
- **Evidence:** FlutterGemma install/load; session-per-task in gemma_inference_adapter.dart
- **Rollback:** N/A (audit only).

---

### P0-T04 — Close active-model identity loop

- **Status:** done
- **Depends on:** P0-T03
- **Objective:** Worker-reported installed/active models must be visible to scheduler (Section 5, 24).
- **Impacted paths:** `src/backend/edgemint/services/worker_registry.py`, worker capability/telemetry reporting
- **Acceptance criteria:** Document whether scheduler reads model residency today; list API/event gaps.
- **Evidence:** workers/enrollment.py installed_models_json; scheduler gap documented
- **Rollback:** N/A (audit + gap list).

---

### P0-T05 — Confirm context / maxTokens guard

- **Status:** done
- **Depends on:** P0-T02
- **Objective:** Context budget MUST be enforced before native runtime invocation (Sections 4, 25).
- **Impacted paths:** `src/apps/worker/lib/inference/llm/`, future `ContextBudgetManager`
- **Acceptance criteria:** Evidence of pre-runtime guard or explicit MISSING with risk note.
- **Evidence:** maxTokens=1280 at load; ContextBudgetManager MISSING
- **Rollback:** N/A.

---

### P0-T06 — Inventory 56 Task Catalog entries

- **Status:** done
- **Depends on:** P0-T01
- **Objective:** Reconcile architecture claim of 56 tasks with `src/shared/task-types/catalog.json` and backend catalog.
- **Impacted paths:** `src/shared/task-types/catalog.json`, `src/backend/edgemint/dev/task_type_catalog.py`, `dsl/`
- **Acceptance criteria:** Table of 56 task type IDs with category (Qwen/Flex/Vision/Other).
- **Evidence:** 56 types catalog.json; plan/evidence/phase-00-catalog-inventory.json
- **Rollback:** N/A.

---

### P0-T07 — Map production vs dev/test paths

- **Status:** done
- **Depends on:** P0-T06
- **Objective:** For each catalog entry, classify execution path: production, dev-only, test-only, missing (Section 66).
- **Impacted paths:** `src/backend/edgemint/dev/portal_api.py`, `src/backend/edgemint/workers/assignments.py`, worker handlers
- **Acceptance criteria:** Per-task path column in audit-matrix or attached table; no task marked production without prod path evidence.
- **Evidence:** 35/56 missing/partial handlers in inventory JSON
- **Rollback:** N/A.

---

### P0-T08 — Document scheduler authority violations

- **Status:** done
- **Depends on:** P0-T01
- **Objective:** Grep worker codebase for forbidden components (Section 2.3): LocalTaskSelector, LocalRetryOrchestrator, LocalReassignmentManager, LocalCloudFallbackDecision.
- **Impacted paths:** `src/apps/worker/lib/`
- **Acceptance criteria:** Forbidden-component table in audit-matrix.md filled; any violations filed as blocking bugs.
- **Evidence:** Forbidden components grep clean; pollAssignment server-driven
- **Rollback:** N/A.

---

### P0-T09 — Produce Phase 0 gap report

- **Status:** done
- **Depends on:** P0-T02, P0-T03, P0-T04, P0-T05, P0-T06, P0-T07, P0-T08
- **Objective:** Consolidate findings into [audit-matrix.md](../audit-matrix.md) with prioritized gaps for Phase 1–3.
- **Impacted paths:** `plan/audit-matrix.md`
- **Acceptance criteria:** Executive summary section added; top 10 gaps ranked with owning phase.
- **Evidence:** audit-matrix.md executive summary
- **Rollback:** Revert summary section.

---

### P0-T10 — Cross-link work-packages.json

- **Status:** done
- **Depends on:** P0-T09
- **Objective:** Map overlapping items in [cursor/work-packages.json](../cursor/work-packages.json) to Phase 0–1 task IDs.
- **Impacted paths:** `plan/phases/phase-00-baseline-correction.md`, `plan/phases/phase-01-assignment-integrity.md`
- **Acceptance criteria:** Each relevant WP ID noted in task blocks (e.g. lease bootstrap WP).
- **Evidence:** audit-matrix.md WP cross-ref table
- **Rollback:** Remove cross-ref lines.

---

### P0-T11 — Phase 0 exit sign-off

- **Status:** done
- **Depends on:** P0-T09, P0-T10
- **Objective:** Confirm Phase 0 acceptance: baseline documented, no false production claims, Phase 1 ready.
- **Impacted paths:** `plan/TODO.md`, `plan/audit-matrix.md`
- **Acceptance criteria:** Phase 0 tasks marked done in TODO; sign-off note with date in audit-matrix.
- **Evidence:** Phase 0 exit sign-off in audit-matrix.md
- **Rollback:** Reopen Phase 0 tasks if new gaps found.
