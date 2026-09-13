# EdgeMint Worker (Flutter)

Production worker shell for device enrollment, model delivery, and mission execution.

## Prerequisites

- Flutter **3.44.x** (see repo `.tool-versions`)
- Dart SDK (bundled with Flutter)

On Windows, Flutter is expected at `C:\Users\Admin\flutter` or set `FLUTTER_ROOT`.

## Iran / restricted network setup

`pub.dev` may return HTTP 403. Use the project mirror helper before any Flutter command:

```powershell
. ..\..\..\tools\flutter_env.ps1   # from src/apps/worker
flutter pub get
flutter analyze
flutter test
flutter test integration_test/enrollment_test.dart
flutter test integration_test/model_delivery_test.dart
flutter test integration_test/execution_runtime_test.dart
python ../../../tests/mobile/run_device_matrix.py --platform android --profile ga1
```

Environment variables set by `tools/flutter_env.ps1`:

- With git/http proxy: `PUB_HOSTED_URL=https://pub.dev`, `FLUTTER_STORAGE_BASE_URL=https://storage.googleapis.com`
- Without proxy: `PUB_HOSTED_URL=https://pub.flutter-io.cn`, `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`

If `pub get` fails on a mirror, set proxy explicitly then rerun:

```powershell
$env:HTTP_PROXY = "http://YOUR_PROXY:3128"
$env:HTTPS_PROXY = $env:HTTP_PROXY
. ..\..\..\tools\flutter_env.ps1
flutter pub get
```

Android Gradle uses mirrors via `tools/setup_gradle_mirror.ps1` (required once per machine).

If you see `no repositories are defined` on project `:gradle`, rerun:

```powershell
powershell -ExecutionPolicy Bypass -File tools\setup_gradle_mirror.ps1
. tools\flutter_env.ps1
```

## Layout

- `lib/api/` — worker HTTP client and canonical route templates
- `lib/config/` — runtime base URL configuration
- `lib/runtime/` — execution coordinator, constraints, checkpoints, inference adapters
- `lib/platform/` — Android foreground service bridge
- `integration_test/` — enrollment, model delivery, and execution runtime tests
- `android/`, `ios/`, `windows/` — platform runners

## Configuration

Override the worker registry base URL at build/run time:

```powershell
flutter run --dart-define=EDGEMINT_WORKER_BASE_URL=https://worker.edgemint.example/v1
```

Default: `http://172.20.34.71:8081` (worker-gateway on the LAN backend host).

**Qwen3-0.6B** uses the LiteRT-LM format from [litert-community/Qwen3-0.6B](https://huggingface.co/litert-community/Qwen3-0.6B). By default the app downloads via the **worker-gateway model proxy** (`GET /models/mdv_qwen3_0_6b/files/Qwen3-0.6B.litertlm`); no Hugging Face token is required on the phone or backend for this model.

### Sideload model (no in-app download)

Download once on the PC and push to the emulator — the app imports on next launch:

```powershell
powershell -ExecutionPolicy Bypass -File tools\push_qwen_model_to_emulator.ps1
```

Target path on device: `/sdcard/Edgemint/models/Qwen3-0.6B.litertlm` (also checks `Download/`). After import, the model stays in app storage and **does not re-download** on restart.

## PaddleOCR (PP-OCRv5 Arabic/Persian, ONNX)

Image pipeline tasks (`document.ocr`, `document.extract`, `image.classify`, `text.summarize` on images) run **PaddleOCR via ONNX Runtime** on Android (`io.edgemint/ocr_runtime`). Structured JSON stages use **Qwen3-0.6B LiteRT** (`QwenTaskProcessor`); images are never sent to the LLM.

| Capability | Backend `taskType` | Pipeline |
|------------|-------------------|----------|
| OCR only | `document.ocr` | OCR → JSON |
| Structured extract | `document.extract` | OCR → Qwen JSON |
| Document classify | `image.classify` | OCR → Qwen JSON |
| Document summarize | `text.summarize` (image input) | OCR → Qwen JSON |
| Text classify | `text.classify` | Qwen only |

Model artifacts (not in Git): `ppocrv5_mobile_det.onnx`, `ppocrv5_mobile_rec_arabic.onnx`, `ppocrv5_arabic_dict.txt`. Pin SHA-256 in `lib/inference/ocr/ocr_models.dart` after export.

Sideload to device (downloads ONNX from GreatV/oar-ocr if missing):

```powershell
powershell -ExecutionPolicy Bypass -File tools\download_paddleocr_models.ps1
powershell -ExecutionPolicy Bypass -File tools\push_paddleocr_models_to_device.ps1
```

Target path: `/sdcard/Edgemint/models/paddleocr/`. On x86 emulators without ONNX models, the worker uses `FakeOcrEngine` for dev E2E while Qwen stays on dev-mock.

Example task manifest: `fixtures/tasks/ocr_extract_text.v1.json`.

Optional build flags (direct Hugging Face download instead of backend proxy):

```powershell
flutter run --dart-define=EDGEMINT_WORKER_BASE_URL=http://172.20.34.71:8081 --dart-define=WORKER_USE_BACKEND_ARTIFACT=false
```

## Verification

```powershell
. ..\..\..\tools\flutter_env.ps1
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter test integration_test/enrollment_test.dart
flutter test integration_test/model_delivery_test.dart
flutter test integration_test/execution_runtime_test.dart
python ../../../tests/mobile/run_device_matrix.py --platform android --profile ga1
```

Native attestation, foreground service, and ONNX/LiteRT adapters are documented in `NATIVE-RUNTIME-CONTRACT.md`.
