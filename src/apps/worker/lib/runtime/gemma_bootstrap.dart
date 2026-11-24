import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

abstract final class GemmaBootstrap {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }

    // Production models are `.litertlm` only. MediaPipe GenAI / image-generator
    // natives added ~60+ MB and are not registered.
    await FlutterGemma.initialize(
      inferenceEngines: [
        LiteRtLmEngine(),
      ],
    );

    _initialized = true;
  }
}
