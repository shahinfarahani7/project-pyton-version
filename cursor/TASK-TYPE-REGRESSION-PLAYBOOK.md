# EdgeMint — task routing, regression and session handoff

Install as `cursor/TASK-TYPE-REGRESSION-PLAYBOOK.md`. Read it together with root `AGENTS.md`. This is a navigation index and working protocol, not a claim of production readiness.

Inspected `origin/gemma` at `4ff88ad0b61b067571d4e23c8bf01d00eae3200a` on 2026-09-27. Always inspect the latest local and fetched remote commits using `AGENTS.md` before an edit. User-local English OCR changes described in recent reports were absent from this remote snapshot; inspect their actual files before acting.

## Start of a new Cursor conversation or task

1. Read root `AGENTS.md`, then this file. Read `START-HERE.md`/`cursor/CURSOR-EXECUTION-ORDER.md` when working on a formal architecture work package; follow the canonical contracts it names. Read `.cursor/rules/architecture-plan-todo.mdc` when changing a plan task.
2. Record branch, local HEAD, fetched upstream SHA and worktree status. Fetch failure means the remote is unverified; preserve local fixes. Inspect recent commits affecting only the likely paths.
3. Choose one route from the table below. Read its files and nearby tests. Search outward with `rg` only if the route or real stack trace requires it. Do not repeatedly scan all 264 Markdown files or the entire repository for each ordinary change.
4. Keep a short session note in the conversation or existing plan/evidence location using [TASK-TYPE-SESSION-NOTE-TEMPLATE.md](TASK-TYPE-SESSION-NOTE-TEMPLATE.md): goal; task type(s); HEAD/upstream; changed paths; protected behavior; commands actually run; PASS/FAIL/BLOCKED/NOT RUN; next action. Update the note after each logical change. Never record access tokens, private inputs or whole verbose logs.
5. At the next Cursor session, read this index and the most recent session note, verify the current Git state and inspect the relevant diff. Reuse the map, not stale claims of passing tests. A changed HEAD, worktree or flags invalidates the corresponding cached verification.

### Fast route table

| Work | Start in source | Existing evidence/tests to inspect |
| --- | --- | --- |
| Add/change task type | `lib/tasks/task_type_mapper.dart`, `mobile_task_dispatcher.dart`, `task_execution_engine.dart`, `lib/runtime/execution_plan_runner.dart` | `test/tasks/task_type_mapper_test.dart`, `test/tasks/task_type_route_regression_test.dart`, `test/tasks/task_type_sequence_regression_test.dart`, `task_execution_engine_test.dart`, `test/runtime/execution_plan_runner_test.dart` |
| OCR/document | `lib/tasks/handlers/ocr_extract_text_handler.dart`, `document_handlers.dart`, `lib/inference/ocr/`, Android `PaddleOcrNativeEngine.kt`, `OcrRuntimePlugin.kt` | `test/inference/ocr_text_normalizer_test.dart`, `test/tasks/`, backend `tests/results/test_document_ocr_validator.py`, native tests if present locally |
| Text summarize | `lib/tasks/handlers/document_handlers.dart`, `lib/inference/llm/qwen_task_processor.dart`, `hierarchical_summarize_pipeline.dart`, `summarize_pipeline_mode.dart` | `test/inference/llm/`, `test/validation/`, backend `tests/results/test_text_summarize_constraints.py` and `test_text_summarize_validator.py` |
| Runtime/model sessions | `lib/runtime/model_runtime_manager.dart`, `gemma_model_runtime_manager.dart`, `gemma_inference_adapter.dart`, `execution_plan_runner.dart` | `test/runtime/model_runtime_manager_test.dart`, `execution_plan_runner_test.dart`, `test/tasks/task_execution_engine_test.dart` |
| Worker auth session | `lib/runtime/worker_session_lifecycle.dart`, `worker_session_store.dart`, API client | `test/runtime/worker_session_lifecycle_test.dart`, enrollment/inbox/heartbeat tests |
| Assignment/lease/upload | `lib/runtime/assignment_coordinator.dart`, `assignment_receiver.dart`, `assignment_output_upload_coordinator.dart` | matching `test/runtime/assignment_*_test.dart`, `test/tasks/task_execution_engine_test.dart` |
| Public contract/portal | `src/shared/task-types/catalog.json`, `src/backend`, portal summarize options/manifest and result validators | backend contract tests, portal workspace tests, worker task mapping/engine tests |

Paths in the table are relative to `src/apps/worker` unless they begin with `src/`. Confirm a path exists in the actual checkout. A source audit of the reviewed remote found some historical README/plan claims out of step with executable OCR and newer local work; use docs to locate contracts, then verify in current code and tests.

## Task-type graph to check on every addition

```text
Public taskType / catalog + input contract
  → backend task creation / assignment manifest
  → TaskTypeMapper.toV1 / pipelineFamily
  → requiresOcr / requiresLlm / vision runtime routing
  → MobileTaskDispatcher.handlerFor
  → ExecutionPlanCatalog.forTaskType / stageExecutesHandler
  → TaskExecutionEngine readiness + handler
  → result schema / backend validation / failure upload
```

Do not add a broad prefix fallback for a new type without testing every old ID it may capture. For example, the reviewed mapper routes `ocr.*` to `document.ocr`, `extract.*` to `document.extract`, some `moderation.*`, `nlp.*` and `llm.*` to `text.classify`, and enumerated vision types to `vision.analyze`. A new ID can be silently sent to an existing handler while its input/result schema differs. Verify both the intended ID and neighboring family IDs. The mapper's `pipelineTypes` and public catalog are different sets; unknown or unsupported catalog types must remain explicit, not silently appear executable.

The dispatcher picks the first handler with a matching capability. When adding a handler, assert no duplicate capabilities, exact handler identity for every supported capability, and a negative unknown-capability case. The execution plan may include stages that only guard/report progress while the handler performs the actual work once. Do not infer one inference call per listed stage. Check `stageExecutesHandler` and the stage/session policy before changing counts.

### Required contract table in tests

Build one readable fixture table from the current catalog/manifest for supported types, for example columns:

| Field | Assert |
| --- | --- |
| `publicId`, `internalCapability` | exact mapping and reverse mapping where defined; duplicates rejected |
| Input kind / options | correct text/image data and task-specific required fields; invalid input fails |
| Handler | exactly one matching handler; no accidental family fallback |
| Runtime | OCR, LLM, vision or lightweight; `ocrOnly` distinguishes hybrid from OCR-only |
| Plan | operations, stage execution decision, resident-model requirement |
| Output/error | expected keys/status and backend acceptance/failure classification |

Use a real representative for each route: OCR-only, OCR+LLM, text classify, short direct summarize, multi-chunk summarize, lightweight image, vision analyze and background removal when those capabilities are actually supported in the checkout. Tests may use deterministic fake inference/OCR to verify wiring; report that this does not prove real-device model accuracy. Add a sequence test **A → B → A** on one engine/controller and after a failing B, so a new handler cannot contaminate earlier task state. Assert readiness calls, session/fence cleanup, call counts and outputs as appropriate. Run the full default worker suite after changes to shared mapper/engine/dispatcher.

Current coverage gap in inspected remote: `task_type_mapper_test.dart` has one example test; `task_execution_engine_test.dart` covers OCR-only, text.classify and plan-binding cleanup; `worker_session_lifecycle_test.dart` covers enrollment/reuse plus storage round-trip. They do not currently prove the whole catalog-to-handler matrix, mixed-type A → B → A, expiry/refresh under time control or native OCR results. Do not claim the test suite already covers these cases.

## Session lifetimes: use the right owner

| Session/state | Owner | Expected reuse / close | Begin with |
| --- | --- | --- | --- |
| Cursor work context | Conversation + this playbook + short verified session note | Re-read note and Git state at new conversation; search only the selected route | `AGENTS.md`, this file |
| Worker identity/auth | `WorkerSessionLifecycle` + encrypted `WorkerSessionStore` | Persist identity; refresh near expiry; register again only on valid missing/rejected credentials | `worker_session_lifecycle.dart`, `worker_session_store.dart` |
| Assignment + fencing | `AssignmentCoordinator`, `ExecutionPlanRunner` | Bound to one assignment/fence; clear in `finally` even on failure/cancel | `assignment_coordinator.dart`, `execution_plan_runner.dart` |
| Resident model | `ModelRuntimeManager`, `GemmaModelRuntimeManager` | Reuse a compatible verified resident model; unload for explicit lifecycle/resource/model change | `model_runtime_manager.dart`, `gemma_model_runtime_manager.dart` |
| LLM chat/inference | `GemmaLiteRtInferenceAdapter` | Fresh chat per inference stage, close on success/error/cancel; drain stopped stream before close | `gemma_inference_adapter.dart` |
| OCR model/session | `PaddleOcrNativeEngine` / plugin | Verify/import/load once as appropriate; close tensors/results, preserve runtime isolation | Android OCR source and native tests |
| Chunk checkpoint | `CheckpointManager` | Resume only under matching assignment fence, source/model/runtime/prompt identity | `checkpoint_manager.dart`, summarize pipeline |

Do not optimize Worker identity or model residency by reusing an inference chat across customers/tasks. Do not conflate `openSessionCount` in an outer guard with actual native `createChat` counts. The old audit at `docs/EdgeMint-Repository-Audit-47608d5.md` explicitly warns these may be different; confirm with current code and logs. `docs/08-sre/runbooks/RB-024-identity-loop-native-crash-evidence.md` calls for separate native-model and inference-session counters.

Session tests for a change here should cover cold start, repeated tasks without redundant registration/model load, token refresh and invalid credential, failure/cancel cleanup, no stale assignment/fence, incompatible model replacement, no unload during active inference and next task after an error. Use a controllable clock or injected state for expiry tests. Live native-handle/thermal/idle soak evidence remains manual and must not be reported as passing by unit tests.

## Documentation authority and conflicts

The repository includes 264 `.md`/`.mdc` files in the inspected commit. Use these entry points rather than reading all files per task:

- `START-HERE.md`, `cursor/CURSOR-MASTER-PROMPT.md`, `cursor/CURSOR-EXECUTION-ORDER.md`, `cursor/STOP-RULES.md`, `cursor/VERIFICATION-PROMPTS.md` govern formal work packages. Their JSON contracts/dependencies remain authoritative for those packages.
- `docs/02-product/task-lifecycle.md`, `worker-lifecycle.md`, `task-revision-attempt-assignment.md` explain lifecycle and fence semantics.
- `docs/00-executive/implementation-order.md` says to prove a paid end-to-end vertical slice before expanding task types.
- `docs/11-testing/strategy.md` and `docs/06-implementation/acceptance-test-plan.md` define broad test layers. Device and operational evidence are distinct from deterministic unit tests.
- `src/apps/worker/README.md` is a setup pointer; its inspected OCR/Qwen3 Arabic model descriptions conflict with the reported local English OCR/Qwen2.5 work. Do not copy its historical model names into current changes without checking source and model manifest.
- `plan/TODO.md` and `.cursor/rules/architecture-plan-todo.mdc` set completion evidence for formal plan tasks. “Done” in a plan does not mean Android/native/live acceptance was run.

If docs and current code conflict, identify the applicable authority and flag the discrepancy in the change report. Fix the stale doc only if within task scope. Do not silently implement obsolete prose or weaken a working code contract to match it.

## Completion checklist

Record the route table row(s) affected, new/old IDs checked, session ownership changes, exact tests/flags and results. Mark any unsupported or untested route explicitly. Cross-type stability is demonstrated by deterministic mapping/handler/plan/result and sequential-state tests; Android Studio receipt/inference checks remain manual. No “system works” claim from one successful task.
