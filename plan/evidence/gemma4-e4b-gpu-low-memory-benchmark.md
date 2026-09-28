# Gemma 4 E4B GPU low-memory benchmark — evidence

**Date:** 2026-09-28 (live execution wave)  
**Branch:** `gemma`  
**Local HEAD:** `b1304b9f783eae29ca6604f769fd2e68ebada42c`  
**Upstream `origin/gemma`:** `b1304b9f783eae29ca6604f769fd2e68ebada42c`  
**NO COMMIT · NO PUSH** · `model.safetensors` untouched (untracked)

---

## Live wave outcome

**Primary status:** **`LIVE_GPU_BENCHMARK_BLOCKED`**  
**Blocker code:** **`LIVE_GPU_BENCHMARK_BLOCKED_NO_ARM_DEVICE`**

Only connected Android target:

```text
sdk gphone64 x86 64 • emulator-5554 • android-x64 • Android 14 (API 34)
```

No ARM64 physical device detected (`flutter devices`). `adb` not on PATH in this environment. Per benchmark spec, **GPU Candidate A vs G comparison was not executed** (x86 emulator is explicitly out of scope for Candidate G).

**Recommendation (no production switch):** **`CURRENT_ARTIFACT_RECOMMENDED`** — no measured RAM/performance data.

**4GB classification:** **`4GB_NOT_TESTED`** (emulator/host not a ~4GB ARM device).

---

## Analyze fix (phase1 harness)

| Check | Before | After |
|-------|--------|-------|
| `flutter analyze --no-pub` | **106 issues**, **1 error** — `test/inference/llm/phase1_live_semantic_harness.dart:122` `Digest.toHex` undefined | **106 issues**, **0 errors** |
| Fix | — | Use `sha256Hex(Uint8List.fromList(utf8Bytes))` from `encrypted_store.dart` (same hex as `Digest.toString()`) |

Scope: **test-only live semantic harness** (gated by `PHASE1_LIVE_INFERENCE`); not production `lib/`. Error was a **real analyzer failure** from invalid `toHex` API usage, not suppressed.

---

## Artifact provisioning (local)

| Candidate | Expected SHA-256 | Expected size | Local download + verified SHA |
|-----------|------------------|---------------|-------------------------------|
| A `gemma-4-E4B-it.litertlm` | `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` | 3_659_530_240 B | **NOT RUN** — blocked by no ARM live path; no `.litertlm` in workspace |
| G `gemma-4-E4B-it-gpu.litertlm` | `4912bb5a9c30993c51a7711f763212077458529312175df0573a78323a2bb7ff` | 2_969_059_328 B | **NOT RUN** — same |

Upstream digests reconfirmed via Hugging Face API (2026-09-28). Artifacts **not** added to Git.

**Production default:** still **Candidate A** (unchanged).

---

## Device record (attempted session)

| Field | Value |
|-------|--------|
| Device model | `sdk gphone64 x86 64` (emulator only) |
| Android version | 14 (API 34) |
| ABI | **android-x64** (not ARM64) |
| SoC | **NOT AVAILABLE** (emulator) |
| Total RAM | **NOT AVAILABLE** (emulator; not used for 4GB cert) |
| Available RAM before test | **NOT RUN** |
| GPU/backend for benchmark | x86 → **CPU** policy; **not valid for Candidate G comparison** |
| Battery / charging / thermal | **NOT RUN** |
| Logcat OOM/LMK | **NOT RUN** |

---

## Benchmark configuration (intended — not executed live)

```text
context: 2048
max output: 256
concurrency: 1
text only
fixture: Gemma4E4bRuntimeBenchmarkFixture
peak sample: 350 ms
run order: A cold, A×3 warm, G cold, G×3 warm, A→G→G→A
```

---

## Measured comparison table (live)

| Metric | Candidate A | Candidate G | Delta |
|--------|---:|---:|---:|
| Artifact size (upstream) | 3_659_530_240 B | 2_969_059_328 B | −19.0% disk only |
| Model load time | NOT RUN | NOT RUN | NOT RUN |
| PSS before load | NOT RUN | NOT RUN | NOT RUN |
| PSS after load | NOT RUN | NOT RUN | NOT RUN |
| Model-load delta | NOT RUN | NOT RUN | NOT RUN |
| Peak inference PSS | NOT RUN | NOT RUN | NOT RUN |
| Min available RAM | NOT RUN | NOT RUN | NOT RUN |
| PSS after session close | NOT RUN | NOT RUN | NOT RUN |
| Run 1 duration | NOT RUN | NOT RUN | NOT RUN |
| Run 2 duration | NOT RUN | NOT RUN | NOT RUN |
| Run 3 duration | NOT RUN | NOT RUN | NOT RUN |
| TTFT | NOT AVAILABLE | NOT AVAILABLE | NOT AVAILABLE |
| Decode TPS | NOT AVAILABLE | NOT AVAILABLE | NOT AVAILABLE |
| Model reload count | NOT RUN | NOT RUN | NOT RUN |
| Session leak | NOT RUN | NOT RUN | NOT RUN |
| Output valid | NOT RUN | NOT RUN | NOT RUN |
| OOM / LMK | NOT RUN | NOT RUN | NOT RUN |

---

## Runtime architecture (unchanged)

```text
Flutter Worker
  → flutter_gemma 1.8.0 / LiteRT-LM
  → GemmaModelRuntimeManager (single load)
  → GemmaLiteRtInferenceAdapter (fresh session per stage)
  → Production: gemma-4-E4B-it.litertlm [A]
  → Benchmark-only registry: gemma-4-E4B-it-gpu.litertlm [G]
```

---

## Automated tests (still green)

```powershell
cd src/apps/worker
flutter test --no-pub test/runtime/worker_model_runtime_candidate_test.dart test/runtime/gemma4_e4b_gpu_benchmark_test.dart
```

**PASS** — 14 tests (2026-09-28 live wave).

Full gate from prior wave: **97 tests PASS** (unchanged by harness fix).

---

## Files touched (live wave)

- `test/inference/llm/phase1_live_semantic_harness.dart` — SHA-256 hex fix
- `plan/evidence/gemma4-e4b-gpu-low-memory-benchmark.md` — this update

---

## Next steps (manual)

1. Connect **ARM64** Android device; ensure `adb` / `flutter devices` shows `android-arm64`.
2. Download A and G to sideload paths (`/sdcard/Edgemint/models/` or Download); verify SHA-256 after download.
3. Run app build with benchmark defines + fixture; capture telemetry phases + logcat.
4. Fill comparison table; apply selection rule; **do not** flip production default without explicit decision.

---

NO COMMIT  
NO PUSH
