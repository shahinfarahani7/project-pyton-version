import 'package:edgemint_worker/runtime/worker_content_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('segmented log parts reconstruct original text', () {
    const chunkSize = WorkerContentDiagnostics.maxPartChars;
    final original = 'αβγ${'x' * (chunkSize * 2 + 17)}end';
    final parts = <String>[];
    final totalParts = (original.length + chunkSize - 1) ~/ chunkSize;
    for (var index = 0; index < totalParts; index++) {
      final start = index * chunkSize;
      final end = (start + chunkSize).clamp(0, original.length);
      parts.add(original.substring(start, end));
    }
    expect(parts.join(''), original);
    expect(
      WorkerContentDiagnostics.sha256Hex(original),
      isNot('empty'),
    );
  });
}
