# EdgeMint — regression prevention and verification rules

## Scope and installation

Place this file at the repository root as `AGENTS.md`. If that file already exists, merge these rules without deleting its existing instructions. Keep `.cursor/rules/architecture-plan-todo.mdc`. Read applicable nested instructions before editing. These rules apply to every code change, not just OCR or summarization.

For task-type changes or a new Cursor conversation, read `cursor/TASK-TYPE-REGRESSION-PLAYBOOK.md` first. It is the task-routing and session-handoff index. If the companion file has not yet been installed, use the paths listed in sections 4–6 below and create the index without altering runtime behavior.

This policy authorizes routine local analysis, deterministic tests and targeted compilation after code changes. Device launches, live inference, Docker restarts, model downloads, deployment and publishing remain explicit/manual actions. A later user instruction prohibiting a check takes precedence: report the check as NOT RUN, never as passed.

Reviewed reference: `origin/gemma`, commit `4ff88ad0b61b067571d4e23c8bf01d00eae3200a`, 2026-09-27. This is an inspected reference, NOT a certified stable release. No builds or tests were executed while preparing this document.

## 1. Establish the real baseline before editing

1. Run `git status --short`, `git branch --show-current`, `git rev-parse HEAD`, and inspect the relevant diff, including new/untracked files.
2. Read the actual implementation, callers, validators, configuration flags and tests. A previous agent report is not proof of current code or passing tests.
3. Do not switch branches, pull/reset, restore whole shared files, delete untracked files or overwrite local changes to reproduce a historical commit. Preserve unrelated work. Fetching a remote reference is read-only; merging is a separate action.
4. State the defect, evidence, files to change, affected contracts and smallest meaningful test set before modifying behavior.
5. For an existing failing test, record the baseline failure before editing. Distinguish pre-existing failures from new failures; neither constitutes a green verification.
6. Inspect all call sites when changing a signature, enum, channel payload or shared helper. Include Dart/Kotlin callers, tests and both flag states.

### Mandatory latest-commit review before every logical change

Before starting each logical edit batch (not every keystroke), review the latest local commit and refresh the remote reference. For this project the expected branch is `gemma`; if the current branch differs, identify its intended upstream instead of switching automatically.

From repository root, for `gemma`:

```powershell
git status --short
git branch --show-current
git log -1 --format=fuller
git show --stat --oneline HEAD
git fetch origin gemma
git log -1 --format=fuller origin/gemma
git show --stat --oneline origin/gemma
git rev-list --left-right --count HEAD...origin/gemma
git log --oneline --left-right HEAD...origin/gemma
git diff --stat HEAD origin/gemma
git diff
git diff --cached
```

- Check every command's exit status. If fetch fails, label the remote reference STALE/UNVERIFIED; never call a cached reference the latest GitHub commit. Local work may continue when its baseline is sufficient, but remote-dependent reconciliation remains blocked.
- Read the latest commit's relevant code diff, not just its message/statistics. Also inspect the most recent commits touching the files being changed, including their regression tests. Use `git log -5 -- <actual-paths>` and `git show <actual-commit> -- <actual-paths>` with resolved paths/IDs, not literal placeholders.
- Inspect relevant `git diff HEAD origin/gemma -- <actual-paths>` and untracked files before deciding what is missing. Distinguish local-only commits, remote-only commits and uncommitted fixes; neither branch is automatically authoritative over the other.
- Record local HEAD, fetched remote SHA, divergence, affected recent fixes and the behavior/tests to preserve in a short pre-edit note. Do not treat the historical SHA in this document as a permanently current baseline.
- If recent commits already fixed the issue, verify that fix instead of implementing it again. If they conflict with the intended change, resolve the design and preserve their regression coverage before editing; do not silently revert them.
- Fetch updates Git references only. It does not authorize pull, merge, rebase, reset, checkout, force-push or overwriting the user's work. Ask only when a conflicting change requires a decision that cannot be safely inferred from the task.
- Re-check HEAD and the working tree before the next edit batch and before reporting completion. If another process changed overlapping files, inspect the new diff and re-evaluate affected checks; do not overwrite it with a stale file copy.

### Important repository/local divergence

At the reviewed remote commit:

- `lib/inference/ocr/ocr_models.dart` still specifies Arabic assets, the old `paddleocr` directory and zero hash/size placeholders.
- `PaddleOcrNativeEngine.kt` still has a whole-image fallback and the earlier detector decoder.
- The later `paddle/PaddleOcrPreprocessPolicy.kt`, activation helpers and Kotlin OCR unit tests described in local reports are absent from this remote snapshot.

Therefore, compare the user's actual local files first. Do NOT restore this old remote OCR implementation over newer local English OCR fixes. Do NOT claim those local fixes are committed, compiled or tested without evidence. Reconcile the difference through a reviewed diff; commit/push only when authorized.

## 2. Fixes must leave a regression check

- For a reproducible behavior bug, add or strengthen a test that fails for the original defect and passes with the fix. Prefer the public production call path with controlled dependencies, not a helper-only assertion.
- A regression test must assert the protected behavior, not just the new implementation's text. Include a valid control case and the relevant failure case.
- Missing imports/exhaustive enum branches require targeted compilation; do not add meaningless tests asserting imports exist.
- Preserve historical fixtures. Never edit expected hashes, erase assertions, skip tests, weaken validators, or change fixtures merely to make a test pass.
- If a contract intentionally changes, document old/new behavior, update its tests with the reason and review downstream compatibility in the same change.
- Exact-byte regressions require exact payloads and verified lengths/hashes. Label reconstructed or synthetic examples honestly; do not call a computed hash a device-verified hash.
- Test files marked “prepared” or “NOT RUN” are not verification evidence.
- Do not use silent `if (!flag) return;` as proof that a gated feature passed. Run the enabling configuration and confirm the test assertions actually execute. Make missing required test configuration visibly skipped or explicitly rejected where appropriate.

## 3. Required checks after each logical change

Run the smallest complete relevant set after each logical change, not after every keystroke. Before reporting completion, run the applicable broader gate below. Reuse results only if no later edits affect them. Do not run unrelated expensive suites for a documentation-only change.

### Common

- Review `git diff` and `git diff --check`; also inspect new files, which ordinary diff can omit.
- Report commands, working directory, exit code, failed/skipped cases and active flags.
- Missing SDK, dependencies, models, network, disk space or database means BLOCKED, not PASS. Do not auto-upgrade tools, delete caches/models, run `flutter clean`, or disable gates to bypass a blocker.
- Use existing lockfiles and project setup. Backend CI uses Python 3.13; worker CI uses Flutter 3.44.0; root package.json requires Node 24/npm 11. Re-check these files if they change.

### Dart/Flutter changes

From `src/apps/worker`:

```powershell
flutter analyze
flutter test <affected-existing-test-paths>
```

Replace the placeholder with real paths; never execute the placeholder literally. Before closing a shared worker/runtime change, also run `flutter test` for the full default suite. Review formatting on changed files only; avoid repository-wide churn.

For summarize/parser/prompt/stage-policy/budget/checkpoint changes, run these additional configurations:

```powershell
flutter test test/validation test/inference/llm test/runtime/checkpoint_manager_test.dart test/runtime/failure_evidence_mapper_test.dart test/runtime/worker_content_diagnostics_test.dart
flutter test test/inference/llm --dart-define=SUMMARIZE_EVIDENCE_V2=true
flutter test test/inference/llm/summarize_facts_only_pipeline_test.dart --dart-define=SUMMARIZE_EVIDENCE_V2=true --dart-define=SUMMARIZE_FACTS_ONLY_PIPELINE=true
```

For diagnostic changes, additionally:

```powershell
flutter test test/inference/llm/summarize_diagnostic_map_test.dart test/inference/llm/summarize_map_prompt_variant_test.dart test/inference/llm/facts_only_experiment_test.dart --dart-define=SUMMARIZE_EVIDENCE_V2=true --dart-define=SUMMARIZE_DIAGNOSTIC_MAP_EVIDENCE=true
```

For flag-resolution/chunk-cap changes, test enabled/disabled, malformed and negative values using the relevant existing tests. A positive-cap configuration is:

```powershell
flutter test test/inference/llm/summarize_chunk_experiment_test.dart --dart-define=SUMMARIZE_EVIDENCE_V2=true --dart-define=SUMMARIZE_EXPERIMENT_SOURCE_CHUNK_TOKENS=1200
```

Inspect flag-dependent assertions before choosing additional matrix cases. An invalid-configuration test should expect rejection, not turn the entire normal suite into an expected failure.

### Kotlin, OCR native code, MethodChannel or Android build changes

`flutter analyze` and Dart tests do NOT compile or validate Kotlin behavior. From `src/apps/worker/android`, using the project's available Gradle wrapper:

```powershell
.\gradlew.bat :app:compileDebugKotlin :app:testDebugUnitTest
```

Check `$LASTEXITCODE` and the test report. `NO-SOURCE`, zero discovered tests, or a missing wrapper is NOT proof of native coverage. The reviewed remote snapshot has no Kotlin OCR test tree or JUnit test dependency; do not claim the reported local test classes exist until inspected. Add focused native tests with a native behavior fix when missing. Do not generate a different Gradle version just to get a wrapper.

For integration/asset/manifest/plugin changes, a packaging check is also needed before declaring the build verified:

```powershell
# From src/apps/worker; does not launch an emulator.
flutter build apk --debug
```

If model assets or SDK/dependencies block packaging, finish safe code/test work and report the exact blocker. Live receipt accuracy remains a separate manual gate.

### Backend changes

From repository root, using the project's Python 3.13 environment:

```powershell
$env:PYTHONPATH = "src/backend"
python -m pytest -q <affected-test-paths>
python -m ruff check src/backend
python -m mypy src/backend/edgemint
```

For shared schemas, routing, failures or manifest changes, run `python -m pytest -q src/backend/tests` before closing. Existing OCR/summarize contract tests are under `src/backend/tests/results/`: `test_document_ocr_validator.py`, `test_text_summarize_constraints.py`, `test_text_summarize_validator.py`. Run the matching worker/portal tests when payload contracts cross those boundaries. Preserve and restore pre-existing shell environment values when appropriate.

### Portal/web changes

From root, use the existing scripts: `npm run lint:web`, `npm run test:web`, `npm run build:web`. For a focused edit, target the relevant workspace first; shared payload/config changes require both affected workspaces. Do not invent script names.

### Contracts, architecture and CI changes

Use the relevant validators listed in `tools/validate_all.sh`; run the full existing contracts gate in CI before merging a contract-wide change. That script includes generators: inspect resulting diffs rather than discarding them automatically. Preserve `.cursor/rules/architecture-plan-todo.mdc` and update its plan evidence honestly.

## 4. Task-type compatibility gate

Adding a task type is a cross-layer contract change. Trace the exact public ID through the canonical catalog, task/manifest schema and options, backend creation/assignment, `TaskTypeMapper.toV1`, `requiresOcr`/`requiresLlm`, `MobileTaskDispatcher.handlerFor`, `ExecutionPlanCatalog.forTaskType`/`stageExecutesHandler`, the concrete handler, runtime readiness, result shape, backend result validator, error/retry policy and upload. Record the expected path in the companion playbook before editing. An unrelated type must not be caught by a broad prefix/family fallback.

First add or extend a table-driven, deterministic test covering every previously supported public type and the new type. For each type assert mapping, handler identity, plan/required runtimes, OCR-only behavior where relevant, and valid output contract; unknown types must fail explicitly. Test two representative sequential executions of different types using the same engine/controller; after a failure/cancellation, verify the next type still runs, no stale assignment/fence/session remains and no unnecessary model or OCR load occurs. Keep focused negative tests for malformed input and unsupported runtime.

Run the existing task/runtime tests as a minimum for every routing or shared execution change:

```powershell
# From src/apps/worker
flutter test test/tasks test/runtime/execution_plan_runner_test.dart test/runtime/model_runtime_manager_test.dart test/runtime/worker_session_lifecycle_test.dart test/runtime/assignment_coordinator_test.dart test/runtime/checkpoint_manager_test.dart
```

If a public task/manifest/result contract changes, run the matching backend and portal contract tests as well. Existing tests cover only examples, not every catalog ID; adding a type is NOT complete until the new table-driven route assertion exercises the entire supported set. Compare the test-discovered type count to the canonical catalog and explicitly classify intentionally unsupported entries; do not assert that every catalog item is executable. Run default worker suite after shared routing changes. Native packaging/device checks remain separate.

Session boundaries must be explicit: persisted Worker authentication/enrollment session (`WorkerSessionLifecycle`/`WorkerSessionStore`), assignment/fence scope (`AssignmentCoordinator`/`ExecutionPlanRunner`), resident model (`ModelRuntimeManager`) and short-lived inference chat (`GemmaLiteRtInferenceAdapter`) are different lifetimes. Reuse an unexpired authenticated session and a compatible resident model; open/close inference sessions per stage as required by the runtime contract. Do not re-register a Worker or reload a model for every task without a proven reason. Never reuse a stale chat/assignment context across tasks or store access tokens in documentation.

## 5. Protected summarize and parser behavior

These safeguards are not a license to freeze a known defect. Changing one requires explicit task scope, a compatibility explanation and updated behavioral tests.

- Route stages through `SummarizeInferenceStage`/policy, not prompt substring guesses.
- Single-chunk production remains `directPublic`; it is not evidence that Map works. Multi-chunk facts-only routing is opt-in for `text.summarize`; do not silently enable it for `document.summarize`.
- Map/intermediate evidence must reject generation truncation and incomplete JSON. No salvage-cut, labeled fallback, completeMissingFields, array trimming or model compact on those stages, including repaired replies.
- Preserve complete-JSON extraction around malformed fences, including an opening brace on the fence line. Preserve narrow literal-escape recovery without altering already-valid JSON strings, paths, quotations or Unicode. Reject ambiguous/truncated recovery inputs according to the existing policy.
- Preserve one shared corrective budget per summarize task. No new budget per chunk or hidden retry. Tests must assert actual normal/corrective call counts.
- Preserve distinct Map evidence; final `keyPointCount` is not a Map array cap. Prompt soft evidence targets are not enforced array limits.
- Facts-only mode retains the v2 shape with empty openItems and priority; reject contract violations rather than silently blanking content. All-empty evidence must not become a successful summary.
- Keep final structured options separate from free-text instructions. Do not infer that “Exactly 4” text sets machine constraints. Verify options through task creation, manifest, prompt and final validator.
- Account for full formatted prompts and overlap. Experiment cap is total Map body including overlap; packing budget subtracts overlap. Test every emitted chunk, ordered source coverage and tail text. Do not claim token estimates are exact tokenizer counts.
- Preserve checkpoint identity isolation by mode/prompt version/cap and existing input/model/runtime identity checks; load and save must agree.
- Preserve local-suffix repetition detection. Repeated wording across JSON fields is not automatically a generation loop. Keep stream-delta assumptions and cancellation diagnostics tested.
- Preserve failure classification consistency across WorkerError, failure upload and backend canonical retry policy. Do not create worker-owned orchestration retries.
- Diagnostics remain isolated from assignment upload and normal production routing. Disabled means inactive; unknown variants must not silently fall back. Preserve model-use locking.
- No reintroduction of the removed Reduce-review experiment as an incidental “fix”.

Existing regression anchors include:

| Contract | Existing worker test files under test/ |
| --- | --- |
| Fence/escape recovery | inference/llm/task_e98fbaac_regression_test.dart; inference/llm/task_f71a56dd_regression_test.dart; validation/literal_escape_json_recovery_test.dart |
| Map preservation/repair | inference/llm/map_evidence_preservation_test.dart; map_json_repair_acceptance_test.dart; qwen_map_truncation_policy_test.dart (same directory) |
| v2 validation/repair | inference/llm/phase2_evidence_strict_validation_test.dart; phase2_evidence_json_repair_test.dart (same directory) |
| Budgets/routing | inference/llm/semantic_chunk_engine_test.dart; summarize_reduce_budget_test.dart; summarize_chunk_experiment_test.dart; summarize_facts_only_pipeline_test.dart (same directory) |
| Repetition/failures | validation/output_repetition_guard_test.dart; runtime/failure_evidence_mapper_test.dart |

## 6. English OCR safeguards — reconcile local code first

These preserve the reported local English implementation; they are NOT claims that the reviewed remote already implements them or that receipt accuracy is established.

- Keep detector/recognizer/dictionary as a matched bundle. Preserve Dart/Kotlin channel payload agreement, import paths and app-private paths. Do not restore Arabic defaults or old caches over the selected English catalog.
- Preserve actual pinned byte sizes/hashes; never replace them with zeros or bypass verification to accept a file. Current inspected English artifacts:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| pp-ocrv5_mobile_det.onnx | 4826518 | 1eb7b4f7ab657ebd1c66d5f79bca7497f29768a2e3c15e52daecbba1a8e4a039 |
| en_pp-ocrv5_mobile_rec.onnx | 7876014 | 8307465d3c9ef2ba4055c3bd0be55aafe11f518630212b7598b70ccb376028ac |
| ppocrv5_en_dict.txt | 1416 | e025a66d31f327ba0c232e03f407ae8d105e1e709e7ccb3f408aa778c24e70d6 |

- Dynamic dimensions are not malformed models. Preserve recognizer H=48 and dynamic width; do not squeeze every wide crop to 320. Preserve aspect resize and post-normalization right padding; label any width resource cap explicitly.
- Keep detector and recognizer preprocessing separate. Reported recognizer policy is BGR CHW, `(pixel/255-0.5)/0.5`. Detector RGB/ImageNet/960 alignment policy remains export-specific and must not be relabeled VERIFIED solely from ONNX shapes.
- Preserve CTC table/class agreement (438 classes for this bundle), blank/duplicate collapse and spaces. Do not trim/drop dictionary entries or silently ignore class mismatch.
- Preserve validated output activation handling: probability tensors are not activated twice. Unsupported activation/layout combinations throw a typed error; exhaustive Kotlin branches must compile.
- No whole-page fallback, fabricated boxes or empty-string success after runtime exceptions. Distinguish a valid no-text image from malformed tensors, missing sessions and inference failures.
- Test heatmap coordinate mapping through resize/padding to original image coordinates. AABB postprocessing is approximate; do not claim polygon/min-area behavior.
- Native tests should cover two text regions, empty heatmap, invalid rank/channel, CTC blank/repeats/space, wide crop/padding, output activations and failure propagation. Android Bitmap dependencies may need an Android-capable test setup; do not hide that requirement with mocks that bypass the algorithm.
- Preserve ONNX/session/tensor cleanup. Exercise disposal/failure paths when resource ownership changes.
- OCR quality acceptance uses image ground truth, especially amounts, IDs and line order. Schema acceptance and model readiness do not establish accuracy. Do not send OCR through Qwen as an unrequested correction step.

## 7. CI follow-through and known gaps

The reviewed `.github/workflows/ci.yml` worker job runs only `flutter pub get`, `flutter analyze`, and default `flutter test`. It does not provide a Kotlin compile/native-test gate or the flag-enabled summarize matrix above.

Rules alone cannot enforce a merge gate. When CI hardening is the task, add those gates with pinned toolchains and deliberate handling of large model assets. Confirm native tests are discovered and flag-gated assertions execute. Do not secretly add model downloads to every CI run. Report missing prerequisites as gaps. Configure required status checks through an authorized repository-settings change, not by claiming this document enforces branch protection.

Known unresolved issues must remain visible: source-segmentation coverage, model-based evidence loss/compression, unwired deterministic merge where applicable, and unproven live OCR accuracy. Do not “protect” an unfixed bug by blessing its output as correct.

## 8. Evidence and completion report

After each logical change, provide:

1. Defect and evidence; exact behavioral change.
2. Files changed and regression test added/updated.
3. Commands + configuration + result, separating PASS / FAIL / BLOCKED / NOT RUN.
4. Compatibility checks across affected modes and layers.
5. Remaining manual/device/semantic checks and any known risk.

Use these distinct outcomes: implemented; deterministic tests passed; native compilation passed; packaging passed; live behavior manually verified. Do not collapse them into “fixed” or “production-ready”. A clean lint result is not compilation proof. A clean Git tree is not correctness proof. Never invent an 80–90% quality score without a stated ground-truth rubric.

Keep a concise regression record in the relevant test/PR or existing project evidence location: bug identifier, protected contract, fixture provenance, test path, command/flags and actual result. Do not store credentials or verbose customer data in committed logs.

When a required gate fails, investigate and fix within scope. If blocked, finish safe work and hand over the exact blocker/command; do not weaken the gate, claim completion or start unrelated experiments. Never commit or push merely because checks passed unless the user authorized it.
