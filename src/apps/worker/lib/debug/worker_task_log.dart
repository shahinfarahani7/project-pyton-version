import 'dart:developer' as developer;

/// Ring buffer + logcat output for Run task with Gemma debugging.
abstract final class WorkerTaskLog {
  static const _maxLines = 100;

  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static void clear() => _lines.clear();

  static void info(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final line = '[$timestamp] $message';
    developer.log(message, name: 'EdgeMintWorker');
    _lines.add(line);
    while (_lines.length > _maxLines) {
      _lines.removeAt(0);
    }
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    final detail = error == null ? message : '$message: $error';
    info('ERROR $detail');
    if (error != null) {
      developer.log(
        detail,
        name: 'EdgeMintWorker',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
