import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef OcrLog = void Function(String message);

/// Verifies sideloaded PP-OCRv5 ONNX artifacts on device storage.
abstract final class PaddleOcrModelInstaller {
  static const _channelName = 'io.edgemint/ocr_runtime';

  static Future<bool> verifyOnDevice({OcrLog? log}) async {
    if (kIsWeb) {
      return false;
    }
    try {
      const channel = MethodChannel(_channelName);
      final ready = await channel.invokeMethod<bool>('isReady');
      if (ready == true) {
        log?.call('PaddleOCR models verified on device');
        return true;
      }
      final imported = await channel.invokeMethod<bool>('importSideloadedModels');
      if (imported == true) {
        log?.call('PaddleOCR models imported from sideload path');
        return true;
      }
    } catch (error) {
      log?.call('PaddleOCR inventory check failed: $error');
    }
    return false;
  }
}
