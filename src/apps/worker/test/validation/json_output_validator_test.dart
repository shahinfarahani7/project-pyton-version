import 'package:edgemint_worker/validation/json_output_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'synthetic_json_extract_fixtures.dart';

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

  test('salvages quoted source text that was left unescaped', () {
    const raw =
        '{"summary":"The tracking screen showed "5 minutes away" for an hour.",'
        '"keyPoints":["Tracking showed "5 minutes away""],'
        '"mainComplaint":"Late delivery",'
        '"suggestedImprovement":"Use driver location",'
        '"missingOrUnclear":[]}';
    final parsed = JsonOutputValidator.parseJsonObject(raw);
    expect(
      parsed?['summary'],
      'The tracking screen showed "5 minutes away" for an hour.',
    );
    expect(parsed?['keyPoints'], ['Tracking showed "5 minutes away"']);
    expect(parsed?['mainComplaint'], 'Late delivery');
  });

  test('rejects two complete top-level objects as ambiguous', () {
    const raw =
        '{"summary":"first","keyPoints":["a"],"missingOrUnclear":[]}'
        '{"summary":"second","keyPoints":["b"],"missingOrUnclear":[]}';
    final extract = JsonOutputValidator.extractJsonObject(raw);
    expect(extract.ok, isFalse);
    expect(
      extract.rejectionReason,
      'json_extract_ambiguous_multiple_objects',
    );
  });

  test('keeps the first object when trailing prose follows it', () {
    const raw =
        '{"summary":"first","keyPoints":["a"],"missingOrUnclear":[]}'
        'trailing prose';
    final parsed = JsonOutputValidator.parseJsonObject(raw);
    expect(parsed?['summary'], 'first');
  });

  test('closes an object truncated at the sequence limit', () {
    const raw =
        '{"summary":"Deliveries were late.",'
        '"keyPoints":["Order A184 arrived at 19:35","Refund is pending"],'
        '"mainComplaint":"Late delivery",'
        '"suggestedImprovement":"The customer should che';
    final parsed = JsonOutputValidator.parseJsonObject(raw);
    expect(parsed?['summary'], 'Deliveries were late.');
    expect(parsed?['keyPoints'], [
      'Order A184 arrived at 19:35',
      'Refund is pending',
    ]);
    expect(parsed?['mainComplaint'], 'Late delivery');
    expect(parsed?.containsKey('suggestedImprovement'), isFalse);
  });

  test('closes an array truncated mid element', () {
    const raw =
        '{"summary":"Deliveries were late.",'
        '"keyPoints":["Order A184 arrived at 19:35","Refund is pen';
    final parsed = JsonOutputValidator.parseJsonObject(raw);
    expect(parsed?['keyPoints'], ['Order A184 arrived at 19:35']);
  });

  test('coerces a bare string into an array field and back', () {
    const schema = <String, dynamic>{
      'summary': 'string',
      'keyPoints': 'array',
      'missingOrUnclear': 'array',
    };
    final coerced = JsonOutputValidator.coerceSchemaTypes({
      'summary': ['Deliveries were late', 'Refund is pending'],
      'keyPoints': ['Order A184 arrived at 19:35'],
      'missingOrUnclear': 'The refund date is not stated.',
    }, schema);

    expect(coerced['summary'], 'Deliveries were late; Refund is pending');
    expect(coerced['missingOrUnclear'], ['The refund date is not stated.']);
    expect(coerced['keyPoints'], ['Order A184 arrived at 19:35']);
    expect(JsonOutputValidator.validateSchema(coerced, schema), isNull);
  });

  test('coercion leaves absent and null fields untouched', () {
    const schema = <String, dynamic>{'keyPoints': 'array'};
    final coerced = JsonOutputValidator.coerceSchemaTypes({
      'other': 'value',
    }, schema);
    expect(coerced.containsKey('keyPoints'), isFalse);
    expect(coerced['other'], 'value');
  });

  test('coerces an empty string into an empty array', () {
    final coerced = JsonOutputValidator.coerceSchemaTypes({
      'missingOrUnclear': '',
    }, const {'missingOrUnclear': 'array'});
    expect(coerced['missingOrUnclear'], isEmpty);
  });

  test('completes only the schema fields a cut-off reply never reached', () {
    const schema = <String, dynamic>{
      'summary': 'string',
      'keyPoints': 'array',
      'suggestedImprovement': 'string',
      'missingOrUnclear': 'array',
    };
    final completed = JsonOutputValidator.completeMissingFields({
      'summary': 'Deliveries were late.',
      'keyPoints': ['Order A184 arrived at 19:35'],
    }, schema);

    expect(completed['summary'], 'Deliveries were late.');
    expect(completed['keyPoints'], ['Order A184 arrived at 19:35']);
    expect(completed['suggestedImprovement'], '');
    expect(completed['missingOrUnclear'], isEmpty);
    expect(JsonOutputValidator.validateSchema(completed, schema), isNull);
  });

  test('quotes keys the model copied bare out of a prompt rule', () {
    // Tail of a real map-stage reply: the model turned two prompt rules into
    // fields, the second one without quotes.
    const raw =
        '{"summary":"Deliveries slipped.",'
        '"keyPoints":["Order A184 arrived at 19:35"],'
        '"mainComplaint":"Late delivery",'
        '"suggestedImprovement":"Use driver location",'
        '"missingOrUnclear":["The refund date"],'
        '"KeepNumbersDatesIdsExact":true,DoNotInventFacts:[]}';
    final parsed = JsonOutputValidator.parseJsonObject(raw);

    expect(parsed?['summary'], 'Deliveries slipped.');
    expect(parsed?['keyPoints'], ['Order A184 arrived at 19:35']);
    expect(parsed?['mainComplaint'], 'Late delivery');
    expect(parsed?['suggestedImprovement'], 'Use driver location');
    expect(parsed?['missingOrUnclear'], ['The refund date']);
  });

  test('quotes a bare key in the first member', () {
    const raw = '{summary:"Deliveries slipped.","keyPoints":[]}';
    final parsed = JsonOutputValidator.parseJsonObject(raw);
    expect(parsed?['summary'], 'Deliveries slipped.');
    expect(parsed?['keyPoints'], isEmpty);
  });

  test('leaves array values and colons inside strings alone', () {
    const raw =
        '{"summary":"Order A184 was due 18:00-19:00.",'
        '"keyPoints":["alpha","beta"]}';
    final parsed = JsonOutputValidator.parseJsonObject(raw);
    expect(parsed?['summary'], 'Order A184 was due 18:00-19:00.');
    expect(parsed?['keyPoints'], ['alpha', 'beta']);
  });

  test('drops trailing junk that cannot be quoted into a key', () {
    const raw =
        '{"summary":"Deliveries slipped.",'
        '"keyPoints":["Order A184 arrived at 19:35"],'
        '"missingOrUnclear":[] then the model kept writing prose}';
    final parsed = JsonOutputValidator.parseJsonObject(raw);
    expect(parsed?['summary'], 'Deliveries slipped.');
    expect(parsed?['missingOrUnclear'], isEmpty);
  });

  test('cuts a looping array down to the contract limits', () {
    // Shape of the device reply that burned its whole output budget repeating
    // one key point, then failed the size check.
    final data = {
      'summary': 'The second order contained regular milk.',
      'keyPoints': [
        'I ordered groceries twice this week',
        'the second order arrived on time',
        'regular milk instead of lactose-free milk',
        ...List.filled(18, 'the milk arrived on time'),
      ],
      'mainComplaint': '',
      'suggestedImprovement': '',
      'missingOrUnclear': <String>[],
    };

    final trimmed = JsonOutputValidator.trimToLimits(data, maxArrayItems: 3);

    expect(trimmed['keyPoints'], [
      'I ordered groceries twice this week',
      'the second order arrived on time',
      'regular milk instead of lactose-free milk',
    ]);
    // Fields the model did fill in survive; the model compaction pass used to
    // lose them.
    expect(trimmed['summary'], data['summary']);
    expect(trimmed.keys, hasLength(5));
  });

  test('cuts an over-long string at a word boundary', () {
    final trimmed = JsonOutputValidator.trimToLimits(
      {'summary': 'alpha beta gamma delta epsilon'},
      maxArrayItems: 3,
      maxStringChars: 20,
    );

    expect(trimmed['summary'], 'alpha beta gamma');
  });

  test('extracts JSON when the opening brace is on the fence line', () {
    const raw =
        '```json {\n'
        '  "summary": "ok",\n'
        '  "keyPoints": ["a"],\n'
        '  "mainComplaint": "",\n'
        '  "suggestedImprovement": "",\n'
        '  "missingOrUnclear": []\n'
        '}\n'
        '`';
    final result = JsonOutputValidator.extractJsonObject(raw);
    expect(result.ok, isTrue, reason: result.rejectionReason);
    expect(result.object!['summary'], 'ok');
  });

  test('returns null when no object is present', () {
    expect(JsonOutputValidator.parseJsonObject('no json here'), isNull);
    expect(JsonOutputValidator.parseJsonObject(''), isNull);
  });

  test('extracts fenced JSON with malformed closing fence and literal newlines',
      () {
    const raw = syntheticLiteralNewlineInSummary;
    final extract = JsonOutputValidator.extractJsonObject(raw);
    expect(extract.ok, isTrue, reason: extract.rejectionReason);
    expect((extract.object!['keyPoints'] as List).length, 4);
  });

  test('preserves curly quote characters in valid JSON strings', () {
    const raw = syntheticValidCurlyQuotesInSummary;
    final extract = JsonOutputValidator.extractJsonObject(raw);
    expect(extract.ok, isTrue, reason: extract.rejectionReason);
    expect(extract.object!['summary'], contains('“five minutes away”'));
  });

  test('extracts JSON after leading prose and opening fence', () {
    const raw =
        'Here is the chunk summary:\n'
        '```json\n'
        '{"summary":"ok","keyPoints":["a"],"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}\n'
        '``';
    final extract = JsonOutputValidator.extractJsonObject(raw);
    expect(extract.ok, isTrue);
    expect(extract.object!['summary'], 'ok');
  });

  test('rejects multiple top-level objects explicitly', () {
    const raw =
        '{"summary":"first","keyPoints":["a"],"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}'
        '{"summary":"second","keyPoints":["b"],"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}';
    final extract = JsonOutputValidator.extractJsonObject(raw);
    expect(extract.ok, isFalse);
    expect(
      extract.rejectionReason,
      'json_extract_ambiguous_multiple_objects',
    );
  });

  test('does not silently complete genuinely truncated JSON', () {
    const raw =
        '{"summary":"Deliveries were late.",'
        '"keyPoints":["Order A184 arrived at 19:35","Refund is pen';
    final extract = JsonOutputValidator.extractJsonObject(raw);
    // Salvage may recover partial facts for non-map repair paths, but must not
    // report a clean top-level object count when braces are unbalanced.
    expect(extract.rejectionStage, isNot('schema'));
    if (extract.ok) {
      expect(extract.object!.containsKey('suggestedImprovement'), isFalse);
    }
  });

  test('parses valid JSON with escaped newlines inside string values', () {
    const raw =
        '{"summary":"Line one\\nLine two","keyPoints":["a"],'
        '"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}';
    final extract = JsonOutputValidator.extractJsonObject(raw);
    expect(extract.ok, isTrue, reason: extract.rejectionReason);
    expect(extract.object!['summary'], 'Line one\nLine two');
  });

  test('preserves backslashes in Windows paths inside valid JSON', () {
    const raw =
        '{"summary":"Saved to C:\\\\Users\\\\test\\\\file.txt","keyPoints":[],'
        '"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}';
    final extract = JsonOutputValidator.extractJsonObject(raw);
    expect(extract.ok, isTrue, reason: extract.rejectionReason);
    expect(extract.object!['summary'], r'Saved to C:\Users\test\file.txt');
  });

  test('preserves unicode escape sequences in valid JSON', () {
    const raw =
        '{"summary":"Letter \\u0041","keyPoints":["\\u0042"],'
        '"mainComplaint":"","suggestedImprovement":"","missingOrUnclear":[]}';
    final extract = JsonOutputValidator.extractJsonObject(raw);
    expect(extract.ok, isTrue, reason: extract.rejectionReason);
    expect(extract.object!['summary'], 'Letter A');
    expect(extract.object!['keyPoints'], ['B']);
  });

  test('recovers fully literal-escape-encoded fenced JSON from live f71 shape',
      () {
    const raw =
        '```json\\n{\\n  \\"summary\\": \\"ok\\",\\n  \\"keyPoints\\": [\\"a\\"],\\n'
        '  \\"mainComplaint\\": \\"\\",\\n  \\"suggestedImprovement\\": \\"\\",\\n'
        '  \\"missingOrUnclear\\": []\\n}\\n```';
    final extract = JsonOutputValidator.extractJsonObject(raw);
    expect(extract.ok, isTrue, reason: extract.rejectionReason);
    expect(extract.literalEscapeRecovered, isTrue);
    expect(extract.object!['summary'], 'ok');
  });

  test('map stage disables salvage-cut while keeping literal-escape recovery', () {
    const salvagedOnly =
        '{"summary":"Deliveries were late.",'
        '"keyPoints":["Order A184 arrived at 19:35"],'
        '"mainComplaint":"Late delivery",'
        '"suggestedImprovement":"The customer should che';
    expect(
      JsonOutputValidator.extractJsonObject(salvagedOnly, allowSalvage: true).ok,
      isTrue,
    );
    expect(
      JsonOutputValidator.extractJsonObject(salvagedOnly, allowSalvage: false).ok,
      isFalse,
    );
  });

  test('rejects truncated literal-escape payload without forcing acceptance',
      () {
    const raw = 'json\\n{\\n  \\"summary\\": \\"Incomplete\\"';
    final extract = JsonOutputValidator.extractJsonObject(raw);
    expect(extract.ok, isFalse);
  });
}
