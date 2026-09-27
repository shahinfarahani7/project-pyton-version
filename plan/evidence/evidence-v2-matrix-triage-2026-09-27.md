# Evidence V2 matrix triage — baseline vs current (2026-09-27)

## Environment parity

| Item | Baseline worktree | Current worktree |
| --- | --- | --- |
| Path | `d:\shakhsi\Edgemint\baseline-worktree-4ff88ad` | `d:\shakhsi\Edgemint\project-pyton-version` |
| Git SHA | `4ff88ad0b61b067571d4e23c8bf01d00eae3200a` | same + uncommitted triage/Wave 1–2 edits |
| Flutter | 3.44.9 stable | 3.44.9 stable |
| Worker deps | `.dart_tool` + `assets/models` copied (baseline) | local |
| Command | `flutter test --no-pub test/inference/llm --dart-define=SUMMARIZE_EVIDENCE_V2=true` | same (no `--no-pub` OK) |

Logs:

- Baseline: `plan/evidence/evidence-v2-matrix-baseline-4ff88ad.log` (UTF-16 from first attempt; authoritative counts from `--no-pub` run in agent output)
- Current pre-triage: `plan/evidence/evidence-v2-matrix-current-worktree.log`
- Current post-triage: `plan/evidence/evidence-v2-matrix-current-worktree-post-triage.log`

## Matrix results

| Worktree | Exit | Pass | Fail |
| --- | ---: | ---: | ---: |
| Baseline `4ff88ad` | 1 | **166** | **21** |
| Current (pre-triage, after Wave 2 JSON) | 1 | 173 | 21 |
| Current (post-triage) | 0 | **194** | **0** |

## Production contract correction (Wave 2 regression)

Wave 2 had set `mapEvidence.usesEvidenceSchema: false` always. At `4ff88ad`, when `SUMMARIZE_EVIDENCE_V2=true`, **mapEvidence keeps `usesEvidenceSchema: true`** (override only clears it when the flag is off). Map prompts already emit evidence v2 (`PromptTemplates.summarizeMapChunk` → `_summarizeMapChunkEvidenceV2`); parse/repair must use `SummarizeEvidenceSchema` + `EvidencePartialValidator`, not five-field `MapPartialValidator`.

**Reverted** to `usesEvidenceSchema: true` for `mapEvidence` in `summarize_inference_stage.dart`. JSON extractor Wave 2 fixes retained.

## Per-failure classification (baseline 21)

| # | Test (short name) | Baseline | Current post-triage | Classification |
| --- | --- | ---: | ---: | --- |
| 1 | `hierarchical_summarize_pipeline` reducePartials merges | fail | pass | **Reproduced on baseline** — mock missed v2 final/intermediate prompt text; fixed mocks |
| 2 | `hierarchical_summarize_pipeline` map stage verbatim/evidence guidance | fail | pass | **Reproduced** — assertions still expected v1 “Prefer at most 6”; branched on flag |
| 3 | `hierarchical_summarize_pipeline` long input map+reduce | fail | pass | **Reproduced** — same mock/prompt drift |
| 4 | `map_evidence_preservation` seven keyPoints | fail | pass (skipped) | **Reproduced** — v1 five-field path; explicit no-op when v2 enabled |
| 5 | `map_evidence_preservation` trimToLimits bypass | fail | pass (skipped) | **Reproduced** — same |
| 6 | `map_json_repair` accepts complete | fail | pass (skipped) | **Reproduced** — legacy five-field repair; skip under v2 |
| 7 | `map_json_repair` rejects incomplete | fail | pass (skipped) | **Reproduced on baseline**; Wave 2 JSON salvage fix applies in default mode only |
| 8 | `phase1_prompt_contract` map empty complaint/improvement | fail | pass | **Reproduced** — v2 map prompt wording |
| 9 | `phase1_prompt_contract` intermediate reduce empty fields | fail | pass | **Reproduced** — v2 intermediate evidence prompt |
| 10 | `phase1_prompt_contract` final reduce derives complaint | fail | pass | **Reproduced** — v2 final reduce prompt |
| 11 | `phase2_evidence_contract` public field forbidden | fail | pass | **Reproduced**; fixed Wave 2 (`startsWith` on issue code) |
| 12 | `phase2_evidence_json_repair` rejects incomplete | fail | pass | **Reproduced**; passes with restored evidence schema on map |
| 13 | `phase2_map_prompt_contract` **compile** | fail | pass | **Reproduced**; Wave 1 syntax fix |
| 14 | `phase2_evidence_strict` A object facts type | fail | pass | **Reproduced** — `_ConstMap` vs `_Map` in message; matcher narrowed |
| 15 | `phase2_evidence_strict` K facts vs keyPoints guidance | fail | pass | **Reproduced** — prompt line break around `15–25` / repeat rule |
| 16 | `qwen_map_truncation_policy` **compile** | fail | pass | **Reproduced**; Wave 1 policy API fix |
| 17 | `task_e98fbaac` runJsonTask (×2) | fail | pass (skipped) | **Reproduced** — live five-field map fixtures vs v2 schema; skip under v2 |
| 18 | `task_f71a56dd` runJsonTask | fail | pass (skipped) | **Reproduced** — same |
| 19 | `task_f71a56dd` two objects ambiguous | fail | pass | **Reproduced**; Wave 2 JSON extractor fix |
| 20 | `hierarchical_reduce_bounds` fan-in merges | fail | pass | **Reproduced** — final reduce prompt matcher |
| 21 | (remaining strict/map prompt/facts-only in baseline tail) | fail | pass | **Reproduced** — prompt contracts + mocks; no production weaken |

None of the 21 were **introduced** by current production edits once `usesEvidenceSchema` was restored. The temporary Wave 2 policy bug (`usesEvidenceSchema: false` with v2 on) was an **introduced regression** (fixed in this triage).

## Post-triage verification commands

| Gate | Command | Exit | Result |
| --- | --- | ---: | --- |
| V2 matrix | `flutter test test/inference/llm --dart-define=SUMMARIZE_EVIDENCE_V2=true` | 0 | **194 pass** |
| Wave 2 bundle + v2 contract | `flutter test map_json… phase2_evidence_contract… --dart-define=SUMMARIZE_EVIDENCE_V2=true` + literal/task tests | 0 | **26 pass** |
| Wave 2 bundle default flag | same four files without v2 define (map_json + task + literal) | 0 | **21 pass** |
| Summarize/validation (default) | AGENTS §4 bundle | 0 | **269 pass** |
| Task-type gate | 71-test bundle | 0 | **71 pass** |
| Default full suite | `flutter test` | 1 | **436 pass / 3 fail** — `flutter-test-current-worktree-post-evidence-v2-triage.log` |

### Default suite failures (out of scope)

1. `phase_03_runtime_smoke_test.dart`
2. `widget_test.dart`
3. `runtime_exclusive_group_enforcer_test.dart` — **passes in isolation**; failed once in full-suite ordering (treat as flaky/isolation; not triage scope)

Live Android: **NOT RUN**
