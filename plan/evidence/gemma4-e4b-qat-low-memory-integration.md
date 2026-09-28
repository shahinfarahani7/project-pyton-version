# Gemma 4 E4B QAT low-memory integration — evidence

**Date:** 2026-09-28  
**Branch:** `gemma`  
**Local HEAD:** `b1304b9f783eae29ca6604f769fd2e68ebada42c`  
**Upstream `origin/gemma`:** `b1304b9f783eae29ca6604f769fd2e68ebada42c` (in sync at time of work)

## Worktree scope (this session)

Model/runtime compatibility gate, removal of safetensors→`.litertlm` rename install path, artifact descriptor metadata, Android process RAM telemetry hooks, format regression tests, APK de-bundling of multi-GB weights. Portal `text.direct` and related task-type work remain in the same worktree from prior edits.

## Current runtime architecture (discovered)

```text
Flutter Worker UI / TaskExecutionEngine
        ↓
QwenTaskProcessor + GemmaLiteRtInferenceAdapter (session-per-inference)
        ↓
GemmaModelRuntimeManager (single resident model)
        ↓
flutter_gemma 1.8.0
        ↓
LiteRtLmEngine + MediaPipeEngine (GemmaBootstrap)
        ↓
gemma-4-E4B-it.litertlm (Candidate A — active)
```

- **flutter_gemma:** 1.8.0 (`pubspec.lock`)
- **flutter_gemma_litertlm:** 1.3.1
- **ModelType:** `ModelType.gemma4`
- **Runtime fileType:** `ModelFileType.litertlm`
- **Registered filename:** `gemma-4-E4B-it.litertlm`
- **modelVersionId:** `mdv_gemma_4_e4b_it`
- **Context (conservative):** 4096 configured; benchmark profile 2048 / 256 output documented in catalog
- **Backend:** GPU on ARM, CPU on x86 emulator
- **Install:** download (HF or proxy) or sideload **`.litertlm` only**; bundled APK asset disabled (was incorrectly bundling safetensors)
- **Residency owner:** `GemmaModelRuntimeManager`
- **Session owner:** `GemmaLiteRtInferenceAdapter` / `withFreshSession`

## Artifacts

| Path | Size | Git | SHA-256 |
|------|-----:|-----|---------|
| `src/apps/worker/assets/models/model.safetensors` | 3_525_094_516 | **untracked** (dir gitignored) | `391946da2e0bec22288e9fe50a4d31d2401c9570ba3baaf0ba43d644dadeb1d4` |
| `gemma-4-E4B-it.litertlm` (Candidate A) | NOT in repo | download/sideload | NOT AVAILABLE locally |

### QAT source checkpoint (Candidate B)

- **Intended HF repo:** `google/gemma-4-E4B-it-qat-mobile-transformers`
- **Local file:** `model.safetensors` only (no `config.json` in same folder in this checkout)
- **Header inspection:** safetensors JSON metadata contains `weight_scale`, `input_activation_scale`, `audio_tower.*` — consistent with **Gemma QAT mobile packed** weights (not plain FP32 tensors)
- **quant_method=gemma:** not read from sidecar JSON here; tensor naming/packing matches Google QAT mobile representation described in LiteRT issues

### Candidate A provenance

- Official/community runtime bundle: [litert-community/gemma-4-E4B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm)
- Documented ~3.66 GB on-device bundle with mixed low-bit decode weights, mmap embeddings, lazy multimodal loaders — **already a QAT-oriented runtime packaging**, not “ naive FP16 E4B ”

## Quantization / export compatibility

| Check | Result |
|-------|--------|
| Run QAT `.safetensors` directly in flutter_gemma | **Blocked** — not a supported runtime format |
| Rename/copy safetensors → `.litertlm` | **Removed** — rejected by content probe (`MODEL_FORMAT_UNSUPPORTED`) |
| `litert-torch export_hf` on QAT mobile `quant_method=gemma` | **QAT_EXPORT_NOT_PRESERVING_QUANTIZATION** / toolchain blocked per Google issues (#1044, #998) |
| Prebuilt `.litertlm` | **Supported** — remains active path |

**Classification:** `QAT_SOURCE_VALID` + `RUNTIME_EXPORT_BLOCKED`

## Changes implemented

- `WorkerModelArtifactDescriptor` + `WorkerModelCatalog.activeRuntimeDescriptor` / `qatMobileSourceDescriptor`
- `WorkerModelFormatGate` — pre-native validation; safetensors rejected with `MODEL_FORMAT_UNSUPPORTED`
- `WorkerModelInstaller` — no safetensors copy; format check before activation
- Android `readDeviceSnapshot` — total/available RAM, lowMemory, process Pss/dirty/heap
- `WorkerProcessMemoryTelemetry` + `DeviceSnapshot` memory fields
- `pubspec.yaml` — removed multi-GB asset bundle from APK
- Tests: `test/runtime/worker_model_format_gate_test.dart`

## Baseline tests (before model-gate edits in this session)

**NOT RUN** as a clean pre-change gate in this session (worktree already contained portal/task-type edits). Prior evidence logs under `plan/evidence/` may reflect older runs; do not treat as this session baseline.

## Final tests (this session)

From `src/apps/worker`:

```powershell
flutter test --no-pub test/tasks test/runtime/execution_plan_runner_test.dart test/runtime/model_runtime_manager_test.dart test/runtime/worker_session_lifecycle_test.dart test/runtime/assignment_coordinator_test.dart test/runtime/checkpoint_manager_test.dart test/worker_api_test.dart test/runtime/worker_model_format_gate_test.dart
```

**Result:** PASS — 82 tests, exit code 0.

```powershell
flutter analyze --no-pub
```

**Result:** FAIL — 108 issues (mostly pre-existing info/warnings; includes unrelated harness errors). Changed model-gate files analyze clean via targeted `dart analyze`.

**Baseline gate before model edits:** NOT RUN (same worktree already contained portal/task-type edits).

## Live Android verification

**NOT RUN** in this session (no device benchmark executed here).

## RAM comparison (required table)

| Metric | Current `.litertlm` (A) | QAT `.safetensors` (B) |
|--------|---:|---:|
| Artifact size | NOT AVAILABLE (not local) | 3_525_094_516 B |
| Available RAM before load | NOT AVAILABLE | NOT AVAILABLE |
| Model-load RAM delta | NOT AVAILABLE | NOT AVAILABLE (not loadable) |
| Inference peak PSS | NOT AVAILABLE | NOT AVAILABLE |
| RAM after session close | NOT AVAILABLE | NOT AVAILABLE |
| Startup time | NOT AVAILABLE | NOT AVAILABLE |
| Inference time | NOT AVAILABLE | NOT AVAILABLE |
| Output valid | NOT AVAILABLE | NOT AVAILABLE |
| Stable A→B→A | NOT AVAILABLE | NOT AVAILABLE |

Instrumentation is in place for a future on-device benchmark run.

## 4 GB device assessment

**NOT_TESTED** — requires constrained real device or faithful low-memory environment with Candidate A `.litertlm` loaded.

## Final selected runtime

**Keep Candidate A:** `gemma-4-E4B-it.litertlm` via existing flutter_gemma / LiteRT-LM stack.

## Integration status (primary)

**C. QAT_SOURCE_VALID_EXPORT_BLOCKED**

Secondary finding aligned with **B. CURRENT_LITERTLM_ALREADY_OPTIMIZED** — official `.litertlm` is the intended low-memory *runtime* representation; raw QAT safetensors is source-only today.

## Remaining blockers

1. Public `export_hf` path for `quant_method=gemma` mobile checkpoints.
2. Optional pinned SHA-256 for official `.litertlm` once artifact is present locally.
3. On-device RAM benchmark script using `WorkerProcessMemoryTelemetry` + controlled 2048/256 profile.
4. 4 GB certification evidence.

---

NO COMMIT  
NO PUSH
