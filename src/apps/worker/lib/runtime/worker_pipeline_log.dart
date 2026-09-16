import 'package:flutter/foundation.dart';

/// Structured pipeline logs visible in `flutter run` terminal output.
abstract final class WorkerPipelineLog {
  static const boot = 'BOOT';
  static const enroll = 'ENROLL';
  static const model = 'MODEL';
  static const heartbeat = 'HEARTBEAT';
  static const assign = 'ASSIGN';
  static const exec = 'EXEC';
  static const api = 'API';

  static void info(String phase, String message) {
    debugPrint('[EdgeMint|$phase] $message');
  }

  static void error(String phase, String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('[EdgeMint|$phase|ERROR] $message${error != null ? ': $error' : ''}');
    if (stackTrace != null && kDebugMode) {
      debugPrint(stackTrace.toString());
    }
  }
}
