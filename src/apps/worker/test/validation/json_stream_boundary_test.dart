import 'package:edgemint_worker/validation/json_stream_boundary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports completion on the closing brace of the top-level object', () {
    final scanner = JsonObjectBoundaryScanner();
    expect(scanner.feed('{"summary":"ok"'), isFalse);
    expect(scanner.feed(',"keyPoints":["a"]'), isFalse);
    expect(scanner.feed('}'), isTrue);
    expect(scanner.isComplete, isTrue);
  });

  test('ignores braces inside string values', () {
    final scanner = JsonObjectBoundaryScanner();
    expect(scanner.feed('{"summary":"a } b"'), isFalse);
    expect(scanner.feed(r'{"escaped":"\""'), isFalse);
    expect(scanner.feed('}}'), isTrue);
  });

  test('waits for nested objects to close', () {
    final scanner = JsonObjectBoundaryScanner();
    expect(scanner.feed('{"outer":{"inner":1}'), isFalse);
    expect(scanner.feed('}'), isTrue);
  });

  test('ignores leading fences and prose before the object', () {
    final scanner = JsonObjectBoundaryScanner();
    expect(scanner.feed('```json\nHere you go: '), isFalse);
    expect(scanner.feed('{"summary":"ok"}'), isTrue);
  });
}
