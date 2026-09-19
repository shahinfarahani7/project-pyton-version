import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

abstract final class GemmaBootstrap {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }

    await FlutterGemma.initialize(
      inferenceEngines: [
        LiteRtLmEngine(),
        MediaPipeEngine(),
      ],
    );

    _initialized = true;
  }
}
