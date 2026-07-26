# GA1 Model Selection and Promotion

The functional selections are fixed:

| Capability | Selected profile | Required runtime | GA1 device tier |
|---|---|---|---|
| `document.ocr` | `paddleocr-mobile` | ONNX Runtime Mobile | T1+ |
| `document.extract` | `gemma-3n-e2b-int4` | LiteRT | T3+ |
| `audio.transcribe` | `whisper-base-int8` | ONNX Runtime Mobile | T2+ |

A selected profile is not a releasable artifact until the model pipeline produces exact bytes, a SHA-256 digest, a KMS-backed signature, SBOM/model BOM, license approval, runtime ABI identifier, golden-set quality report, resource envelope, thermal/energy report, and real-device benchmark matrix. The promotion process writes these facts to `evidence/actual/models/` and never edits the canonical profile to insert guessed values.

Non-GA1 profiles remain evaluation-only and cannot be routed in production.
