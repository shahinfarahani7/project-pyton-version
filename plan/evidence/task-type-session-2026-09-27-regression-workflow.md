# Task-type regression session — 2026-09-27

## Final acceptance verification (latest)

**Branch:** `gemma` · **HEAD:** `4ff88ad0b61b067571d4e23c8bf01d00eae3200a` (uncommitted) · **CWD:** `src/apps/worker`

### Task-type gate — 67 vs 71 vs 75

| Command variant | Pass count | Exit |
| --- | ---: | ---: |
| AGENTS.md §4 (no `worker_api_test.dart`) | **67** | 0 |
| Documented 71-test bundle (+ `test/worker_api_test.dart`) | **75** | 0 |
| Wave 3 log (omitted `worker_api_test.dart`) | **67** | 0 |

**Why Wave 3 reported 67:** Wave 3 ran the AGENTS.md path only and **omitted** `test/worker_api_test.dart` (4 tests: enrollment, model delivery, execution routes, `WorkerApiException`). Restored complete gate per `plan/evidence/flutter-test-failure-baseline-2026-09-27.md` includes `worker_api_test.dart`.

**Why acceptance shows 75:** Same restored command after adding **4** focused `TaskExecutionEngine` tests (map-reduce shell, catalog policy, direct mock path, failure cleanup). Prior baseline was **71** before those tests.

```powershell
flutter test test/tasks test/runtime/execution_plan_runner_test.dart test/runtime/model_runtime_manager_test.dart test/runtime/worker_session_lifecycle_test.dart test/runtime/assignment_coordinator_test.dart test/runtime/checkpoint_manager_test.dart test/worker_api_test.dart
```

Log: `plan/evidence/flutter-test-task-type-gate-final-2026-09-27.log`

### Evidence V2 matrix vs broader flagged gate

| Gate | Command | Files | Pass | Exit | Log |
| --- | --- | --- | ---: | ---: | --- |
| **Exact V2 matrix** | `flutter test test/inference/llm --dart-define=SUMMARIZE_EVIDENCE_V2=true` | 28 files under `test/inference/llm/*_test.dart` | **201** | 0 | `flutter-test-evidence-v2-matrix-exact-2026-09-27.log` |
| **Broader flagged gate** | `flutter test test/validation test/inference/llm test/runtime/checkpoint_manager_test.dart test/runtime/failure_evidence_mapper_test.dart test/runtime/worker_content_diagnostics_test.dart --dart-define=SUMMARIZE_EVIDENCE_V2=true` | all of `test/validation/` + same 28 LLM tests + 3 runtime tests | **276** | 0 | `flutter-test-flagged-gate-final-2026-09-27.log` |
| **Default summarize/validation** | same paths without `--dart-define` | same as broader minus flag | **276** | 0 | `flutter-test-summarize-gate-final-2026-09-27.log` |

### Other deterministic Dart gates

| Command | Pass | Exit | Log |
| --- | ---: | ---: | --- |
| `flutter test` (full default suite) | **450** | 0 | `flutter-test-full-suite-final-2026-09-27.log` |
| `flutter analyze` (all changed/untracked worker Dart vs `4ff88ad`) | **31 warnings**, 0 errors | 1 | `flutter-analyze-final-acceptance-2026-09-27.log` |
| `flutter analyze` (production + new engine/widget/support only) | **3 warnings** (assignment_coordinator `!`) | 1 | — |

### Production diff inventory (`git diff 4ff88ad`)

| File | Summary |
| --- | --- |
| `lib/runtime/assignment_coordinator.dart` | Signature / coordinator adjustments (local vs baseline). |
| `lib/tasks/task_execution_engine.dart` | Map-reduce plan when injected `ExecutionPlanRunner` + summarize plan; reuse precomputed `plan` in `runPlanForScope`. |
| `lib/telemetry/resource_envelope_catalog.dart` | Resource envelope entries extended. |
| `lib/validation/json_output_validator.dart` | JSON extract/repair/literal-escape ordering and salvage fixes. |
| `src/shared/task-types/catalog.json` | Catalog entries (non-Dart). |

### Test / support diff (high level)

- Summarize JSON + Evidence V2 regression tests under `test/inference/llm/`
- `test/tasks/task_type_route_regression_test.dart`, `task_type_sequence_regression_test.dart` (untracked)
- `test/support/summarize_contract_mock_runner.dart`, `fixtures/summarize_v2_prompt_matchers.dart`
- Wave 3: `phase_03_runtime_smoke_test.dart`, `widget_test.dart`, `checkpoint_manager_test.dart` (V2 resume)
- Acceptance: **4** new cases in `test/tasks/task_execution_engine_test.dart`

### TaskExecutionEngine acceptance tests

1. Injected runner + `text.summarize` → `sessionCount > 0`, binding cleared, `openSessionCount == 0`.
2. `QwenTaskProcessor()` `requiresNativeRuntime` + catalog contains `chunk` / `llm_map` / `llm_reduce`.
3. Mock LLM without injected runner → summarize succeeds without opening sessions on unused plan memory.
4. Invalid summarize JSON through injected plan → `retryable`, binding cleared, no open sessions.

### Widget test readiness

`widget_test.dart` pumps `WorkerHomeTab` with controlled `WorkerAppController` (offline gateway, in-memory store, availability off). Asserts **production copy**: “Ready for missions”, “Worker availability”, and `WorkerModelCatalog.displayName` on the prepare/download affordance — not merely “no throw”.

### Unresolved verification (not claimed)

| Item | Status |
| --- | --- |
| Kotlin compile / `:app:testDebugUnitTest` | **NOT RUN** |
| `flutter build apk --debug` | **NOT RUN** |
| Live Android / device OCR or summarize | **NOT RUN** |
| End-to-end `TaskExecutionEngine` with native Gemma resident (no test `runner`) | **NOT RUN** (unit tests use mock LLM or catalog policy only) |
| `flutter analyze` clean on entire changed test tree | **OPEN** — 31 infos/warnings (mostly `inference_failure_on_collection_literal` in existing LLM tests) |

---

## Wave 3 — smoke + widget recovery

See prior section in git history; full suite green after fixes.

## Enforcer + v2 map coverage pass

Fixed enforcer flake; v2 map coverage; Evidence V2 triage docs under `plan/evidence/`.
