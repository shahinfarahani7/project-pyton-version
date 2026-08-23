# Qwen, Flex, and Vision completion — 2026-08-22

## Outcome

The 56-type catalog now has an explicit production runtime path for every type:

| Group | Types | Runtime path | Real execution evidence |
|---|---:|---|---|
| OCR | 5 | PaddleOCR | Previously validated real OCR/PDF path |
| Lightweight vision | 3 | deterministic local image algorithms | Previously validated |
| Qwen text/document | 25 | Qwen3-0.6B + LiteRT-LM | 25/25 schema passes |
| Flex | 9 | specialized structured contracts + Qwen3-0.6B | 9/9 schema passes |
| Semantic vision | 13 | InternVL3-1B + strict schema + bounded Qwen repair + consistency gate | 13/13 accepted runtime outcomes |
| Background removal | 1 | MediaPipe SelfieSegmenter TFLite | real 256×256 mask and transparent PNG pass |

This closes the missing-runtime and missing-contract infrastructure blockers. It does **not** constitute a production accuracy certification for moderation/safety models; that requires a labeled, diverse evaluation corpus and target-device release testing.

## Implemented

- Preserved `sourceTaskType` after internal routing so specialized prompts are no longer collapsed into generic classifiers.
- Added exact instructions, required fields, and output schemas for 25 Qwen, 9 Flex, and 13 semantic-vision types.
- Added required-field validation for all Flex input contracts.
- Added real InternVL image-message execution through `flutter_gemma`/LiteRT-LM.
- Added automatic InternVL download, streaming SHA-256 verification, and exact-model re-selection.
- Added bounded Qwen JSON repair for malformed VLM output.
- Added visual consistency checks for score ranges, risk/decision contradictions, schema placeholders, unsupported logo claims, and unresolved allowed/safe decisions.
- Added conservative fallback: unresolved safety results become high-risk/human-review; catalog results become zero-confidence/empty-evidence instead of invented labels.
- Added native Android MediaPipe Image Segmenter with a real confidence mask converted to PNG alpha.
- Added PNG, JPEG, WebP, and GIF raster validation while keeping PDF acceptance limited to OCR paths.

## Real model results

- Qwen model: `Qwen3-0.6B.litertlm`, 614,236,160 bytes, SHA-256 `555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4`.
- InternVL model: `InternVL3-1B.litertlm`, 737,985,904 bytes, SHA-256 `c1f0dfd2794a5bcb315810099e0a0e3f774ee6b7244107c7d5ed0c0172d20279`.
- Segmentation model: `selfie_segmenter.tflite`, 249,537 bytes, SHA-256 `191ac9529ae506ee0beefa6b2c945a172dab9d07d1e802a290a4e4038226658b`.
- 25 Qwen contracts: 25 passed, 0 failed, 102,149 ms.
- 9 Flex contracts: 9 passed, 0 failed, 36,673 ms.
- 13 semantic visual contracts: 13 passed, 0 failed, 152,487 ms; 11 required bounded Qwen repair and 2 used conservative human-review fallback. Per-task evidence is in `artifacts/real-vision-13-contracts.json`.
- Segmentation: XNNPACK CPU, input `[1,256,256,3]`, output `[256,256]`, inference 5 ms on the smoke fixture.
- Control plane: 20 workers × 56 types = 1,120 assignment flows; 1,120 stale-fence rejections; 0 failures.

## Verification commands

```bash
python tools/verify_task_catalog_infrastructure.py
python tools/run_56_task_protocol_load.py
python tools/run_real_qwen_contract_matrix.py /path/Qwen3-0.6B.litertlm
python tools/run_real_flex_contract_matrix.py /path/Qwen3-0.6B.litertlm
python tools/run_real_vision_13_contract_matrix.py /path/InternVL3-1B.litertlm /path/Qwen3-0.6B.litertlm /path/test.png
python tools/run_real_segmentation_smoke.py /path/selfie_segmenter.tflite /path/test.png
```

## Remaining release gates

1. Build and run the Android APK on the actual release Flutter/Android toolchain. This Linux workspace had only a Windows `local.properties`, so Dart parsing/formatting was checked but a target APK was not produced here.
2. Run the PostgreSQL-dependent portal/API tests; 8 tests were skipped because PostgreSQL was unavailable in this workspace.
3. Evaluate the 13 VLM tasks against a labeled safety/catalog dataset. A single product image validates runtime, routing, repair, consistency, and fallback behavior—not precision/recall.
4. Measure memory, thermal throttling, download resume, and latency on each supported device tier with both 614 MB Qwen and 738 MB InternVL installed.
