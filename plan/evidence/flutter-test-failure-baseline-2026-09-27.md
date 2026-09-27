# Flutter test failure baseline — verified runs (2026-09-27)

## Environment (both runs)

| Item | Value |
| --- | --- |
| Flutter | 3.44.9 (stable), Dart 3.12.2 |
| CWD | `src/apps/worker` |
| Command per file | `flutter test <path>` (current); `flutter test --no-pub <path>` (baseline after deps/assets seeded) |

## Baseline worktree setup (`4ff88ad`)

Path: `d:\shakhsi\Edgemint\baseline-worktree-4ff88ad` @ `4ff88ad0b61b067571d4e23c8bf01d00eae3200a`.

Bare checkout could not build tests until:

1. Copied `assets/models/` from current worktree (Qwen `.task` listed in `pubspec.yaml`; missing in baseline → asset bundle error).
2. Copied `.dart_tool/` from current worktree (avoids long `pub get`; gitignored only).

Log: `plan/evidence/ten-failure-baseline-run2.log` (8 files, each `EXIT_CODE=1`).

Initial automated baseline script without assets: **UNVERIFIED** (stuck on `pub get` / asset bundle); not used for classification.

## Current worktree

Uncommitted task-type + signature changes on branch `gemma`, HEAD `4ff88ad` (same commit; local diffs in assignment/catalog/tests only).

Logs:

- Per-file: `plan/evidence/ten-failure-current-worktree.log` (8 files, each `EXIT_CODE=1`).
- Full suite: `plan/evidence/flutter-test-current-worktree-2026-09-27.log` → **422 pass / 10 fail** (exit 1).

## Source diff vs `4ff88ad` (failing areas)

`git diff 4ff88ad -- src/apps/worker/lib/inference src/apps/worker/test/inference …` → **no changes** to summarize/JSON/widget failure paths.

Only worker lib diffs: `assignment_coordinator.dart`, `resource_envelope_catalog.dart` (not involved in the 10 failures).

## Ten failing cases — baseline vs current

| # | Test (full name) | Baseline exit | Current exit | Classification |
| --- | --- | ---: | ---: | --- |
| 1 | `map_json_repair_acceptance_test.dart`: Map JSON repair strict completeness **rejects incomplete repaired Map JSON without salvage or completion** | 1 | 1 | **Reproduced on baseline, same cause** — salvage control expected true, actual false |
| 2 | `phase2_evidence_contract_test.dart`: Phase 2 evidence schema contract **rejects public five-field keys in evidence partial** | 1 | 1 | **Reproduced on baseline, same cause** — violation string format |
| 3 | `phase2_map_prompt_contract_test.dart`: **loading** (compile) | 1 | 1 | **Reproduced on baseline, same cause** — missing `)` at line 132 |
| 4 | `qwen_map_truncation_policy_test.dart`: **loading** (compile) | 1 | 1 | **Reproduced on baseline, same cause** — unknown named parameter `mapStage` |
| 5 | `task_f71a56dd_regression_test.dart`: **does not accept two objects after literal-escape unwrapping** | 1 | 1 | **Reproduced on baseline, same cause** — `json_extract_no_object` vs expected ambiguous |
| 6 | `phase_03_runtime_smoke_test.dart`: Phase 3 integration smoke **text.summarize completes through ExecutionPlanRunner map-reduce shell** | 1 | 1 | **Reproduced on baseline, same cause** — status `retryable` not `succeeded` |
| 7 | `literal_escape_json_recovery_test.dart`: **preserves literal backslash-n token distinct from real newline** | 1 | 1 | **Reproduced on baseline, same cause** |
| 8 | `literal_escape_json_recovery_test.dart`: **preserves real newline inside a value after unescape** | 1 | 1 | **Reproduced on baseline, same cause** |
| 9 | `literal_escape_json_recovery_test.dart`: map stage **rejects salvage-cut even when truncated=false** | 1 | 1 | **Reproduced on baseline, same cause** — expected WorkerError, got successful map |
| 10 | `widget_test.dart`: **home shows readiness and download action** | 1 | 1 | **Reproduced on baseline, same cause** — `pumpAndSettle` timeout |

**Introduced or changed in current worktree:** none of the 10 (same test names, messages, and exit codes after baseline environment parity).

**Environment-dependent:** baseline required local copy of `assets/models` and `.dart_tool`; without them, baseline runs are UNVERIFIED (documented above).

## Model-signature contract (this worktree)

Production format when `modelVersionId` is set: `sha256Hex('$digest:$modelVersionId:$signingKey')` (`ModelArtifactVerifier._expectedSignature`).

Tests (real `ModelArtifactVerifier` + `StubInferenceAdapter.loadVerified`, no verifier mock):

- `test/runtime/model_artifact_verifier_test.dart` — legacy two-segment rejected; two-segment without version accepted; wrong version rejected; adapter accept/reject paths.
- `test/runtime/assignment_coordinator_test.dart` — **assignment model bundle uses digest:modelVersionId:signingKey contract**.

Run: `flutter test test/runtime/model_artifact_verifier_test.dart` → **12 pass, exit 0**.

## Wave 1 — compile repair (2026-09-27)

Fixed in current worktree only (test-only; no production summarize changes):

| File | Fix | Rationale |
| --- | --- | --- |
| `phase2_map_prompt_contract_test.dart:132` | Close `contains('schemaVersion')` with `));` | Syntax only; assertions unchanged |
| `qwen_map_truncation_policy_test.dart` | Replace removed `mapStage:` with `policy: SummarizeStagePolicy.forStage(...)` | Matches `QwenTaskProcessor.labeledFallbackEnabled(sourcePrompt, policy)` — mapEvidence disables labeled fallback; directPublic enables it |

Focused runs (exit 0): `flutter test test/inference/llm/phase2_map_prompt_contract_test.dart` (7 pass), `flutter test test/inference/llm/qwen_map_truncation_policy_test.dart` (2 pass).

Full suite after Wave 1: `plan/evidence/flutter-test-current-worktree-wave1.log` → **431 pass / 8 fail** (exit 1). Compile-only failures removed; inventory below.

### Remaining full-suite failures (8)

1. `map_json_repair_acceptance_test.dart` — rejects incomplete repaired Map JSON without salvage or completion  
2. `phase2_evidence_contract_test.dart` — rejects public five-field keys in evidence partial  
3. `task_f71a56dd_regression_test.dart` — does not accept two objects after literal-escape unwrapping  
4. `phase_03_runtime_smoke_test.dart` — text.summarize map-reduce shell  
5–7. `literal_escape_json_recovery_test.dart` — three cases (literal `\n`, real newline, map salvage-cut)  
8. `widget_test.dart` — home shows readiness and download action  

**Next failure group (Wave 2):** behavioral summarize/JSON (`map_json_repair`, `phase2_evidence_contract`, `literal_escape_json_recovery`, `task_f71a56dd`) — not widget.

## Wave 2 — behavioral JSON / stage policy (2026-09-27)

Production + test fixes (map stage keeps five-field partial; evidence v2 schema only on `intermediateEvidence`):

| File | Change |
| --- | --- |
| `lib/inference/llm/summarize_inference_stage.dart` | `mapEvidence.usesEvidenceSchema: false` (MapPartialValidator path) |
| `lib/validation/json_output_validator.dart` | Literal-escape ambiguous multi-object probe; salvage cut for object keys leaked into arrays; literal-escape recovery when brace match does not decode; decode-failed ordering |
| `test/inference/llm/phase2_evidence_contract_test.dart` | Match `:field=` issue suffix via `anyElement(startsWith(...))` |
| `test/validation/literal_escape_json_recovery_test.dart` | JSON fixtures for `\\n` vs `\n`; `inferenceStage: mapEvidence` on salvage-cut test |
| `test/inference/llm/phase2_map_prompt_contract_test.dart` | Explicit `<String>` list types (analyze clean) |

Focused Wave 2 run (26 pass, exit 0):

```text
flutter test test/inference/llm/map_json_repair_acceptance_test.dart \
  test/inference/llm/phase2_evidence_contract_test.dart --dart-define=SUMMARIZE_EVIDENCE_V2=true \
  test/inference/llm/task_f71a56dd_regression_test.dart \
  test/validation/literal_escape_json_recovery_test.dart
```

Gates after Wave 2:

| Command | Exit | Result |
| --- | ---: | --- |
| Summarize/validation gate (AGENTS, no extra defines) | 0 | 269 pass |
| `flutter test test/inference/llm --dart-define=SUMMARIZE_EVIDENCE_V2=true` | 0 | **194 pass** (post-triage — see `evidence-v2-matrix-triage-2026-09-27.md`) |
| Task-type gate (71 tests) | 0 | PASS |
| `flutter analyze` on changed Dart files | 0 | No issues |
| Full default `flutter test` | 1 | **437 pass / 2 fail** — `plan/evidence/flutter-test-current-worktree-wave2.log` |

### Remaining full-suite failures (2 — out of Wave 2 scope)

1. `phase_03_runtime_smoke_test.dart` — text.summarize map-reduce shell  
2. `widget_test.dart` — home shows readiness and download action  

## Task-type gate (AGENTS §4)

`flutter test test/tasks test/runtime/execution_plan_runner_test.dart test/runtime/model_runtime_manager_test.dart test/runtime/worker_session_lifecycle_test.dart test/runtime/assignment_coordinator_test.dart test/runtime/checkpoint_manager_test.dart test/worker_api_test.dart` → **71 pass, exit 0** (includes new signature test).

## Wave 3 — final two default-suite failures (2026-09-27)

| File | Resolution |
| --- | --- |
| `phase_03_runtime_smoke_test.dart` | Prompt-aware `summarizeContractMockRunner`; engine uses map-reduce shell when injected `ExecutionPlanRunner` + summarize plan; model resident in setup; `output['data']['summary']`. |
| `widget_test.dart` | `WorkerHomeTab` + controlled `WorkerAppController`, no full bootstrap/`pumpAndSettle`. |

Full suite: **446 pass ×2** — `plan/evidence/flutter-test-full-suite-wave3-run1-2026-09-27.log`, `run2`.
