import 'package:flutter/widgets.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import '../models/gemma_model_catalog.dart';

/// Initializes flutter_gemma once for LiteRT-LM inference.
abstract final class GemmaBootstrap {
  static var _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    WidgetsFlutterBinding.ensureInitialized();
    FlutterGemma.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
      huggingFaceToken: GemmaModelCatalog.huggingFaceTokenFromEnvironment(),
      maxDownloadRetries: 10,
    );
    _initialized = true;
  }
}
