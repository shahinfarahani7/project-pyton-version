import 'package:edgemint_worker/validation/json_output_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses JSON after stripping think blocks', () {
    const raw = '<think>internal reasoning</think>{"label":"invoice","confidence":0.9}';
    final parsed = JsonOutputValidator.parseJsonObject(raw);
    expect(parsed?['label'], 'invoice');
  });

  test('repairs markdown fenced JSON', () {
    const raw = '''
```json
{"summary":"hello","keyPoints":["a"],"missingOrUnclear":[]}
```
''';
    final parsed = JsonOutputValidator.parseJsonObject(raw);
    expect(parsed?['summary'], 'hello');
  });
}
