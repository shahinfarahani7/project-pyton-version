import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

abstract final class GemmaBootstrap {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }

    await FlutterGemma.initialize(
      inferenceEngines: [
        MediaPipeEngine(),
      ],
    );

    _initialized = true;
  }
}