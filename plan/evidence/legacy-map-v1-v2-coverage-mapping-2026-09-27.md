# Legacy map tests — v1 no-op vs v2 coverage (2026-09-27)

When `SUMMARIZE_EVIDENCE_V2=true`, map chunk prompts and `mapEvidence` parsing use **evidence v2** (`schemaVersion`, `facts`, `openItems`, `priority`). Five-field map partial contracts apply only when the flag is **off**.

| File / test (v1 no-op when v2 on) | V1 behavior protected | V2 coverage |
| --- | --- | --- |
| `map_json_repair_acceptance_test.dart` (3 tests) | JSON repair on five-field map partial; no salvage on map stage; single corrective budget | `phase2_evidence_json_repair_test.dart` (complete/incomplete evidence repair); **new:** `Map JSON repair at mapEvidence when evidence v2 is active` rejects five-field output |
| `map_evidence_preservation_test.dart` (2 tests) | Seven `keyPoints` preserved; no `trimToLimits` on map path | **new group:** facts preserved + envelope round-trip; rejects five-field; no trim on `facts` |
| `task_e98fbaac_regression_test.dart` (2 runJsonTask tests) | Live five-field fixtures parse through map stage without repair | Extractor/hash tests unchanged; **new:** `runJsonTask rejects legacy five-field payload when evidence v2 active` |
| `task_f71a56dd_regression_test.dart` (1 runJsonTask test) | Same for f71 fixture | Extractor/ambiguous tests unchanged; **new:** v2 rejection test |
| `summarize_facts_only_pipeline_test.dart` | (existing flag gate — facts-only requires v2) | Already v2-only when enabled |
| `summarize_diagnostic_map_test.dart` | Diagnostic map when v2 off | v2 diagnostic path when on |

**Stage policy (both flag modes):** `summarize_stage_policy_v2_test.dart` — `mapEvidence` / `intermediateEvidence` `usesEvidenceSchema` tracks compile flag; `directPublic` stays false.

**Not no-ops:** `phase2_evidence_json_repair_test.dart`, `phase2_evidence_strict_validation_test.dart`, `phase2_map_prompt_contract_test.dart` — require v2 define and run real assertions.
