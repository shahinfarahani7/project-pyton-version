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

- `PUB_HOSTED_URL=https://pub.myket.ir`
- `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`

Android Gradle is configured with `https://maven.myket.ir` for dependency resolution.

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

Gemma **gemma-3n-e2b-int4** uses the LiteRT-LM format from [google-ai-edge/LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM). The model file is downloaded at runtime from Hugging Face (accept the Gemma license there). Optional build flags:

```powershell
flutter run --dart-define=EDGEMINT_WORKER_BASE_URL=http://172.20.34.71:8081 --dart-define=HUGGINGFACE_TOKEN=hf_...
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
