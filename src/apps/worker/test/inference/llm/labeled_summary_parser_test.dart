import 'package:edgemint_worker/inference/llm/labeled_summary_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds the five summary fields from labelled lines', () {
    const raw = '''
SUMMARY: Deliveries slipped on the last three orders.
POINT: Order A184 arrived at 19:35 instead of 18:00-19:00.
POINT: Tracking kept showing five minutes away.
POINT: A refund was charged twice.
COMPLAINT: Late deliveries and unreliable estimates.
IMPROVEMENT: Recalculate estimates from the driver location.
MISSING: The refund date is not stated.
''';

    final parsed = LabeledSummaryParser.parse(raw);

    expect(parsed?['summary'], 'Deliveries slipped on the last three orders.');
    expect(parsed?['keyPoints'], hasLength(3));
    expect(
      (parsed?['keyPoints'] as List).first,
      'Order A184 arrived at 19:35 instead of 18:00-19:00.',
    );
    expect(parsed?['mainComplaint'], 'Late deliveries and unreliable estimates.');
    expect(
      parsed?['suggestedImprovement'],
      'Recalculate estimates from the driver location.',
    );
    expect(parsed?['missingOrUnclear'], ['The refund date is not stated.']);
  });

  test('ignores prose, bullets and echoed placeholders', () {
    const raw = '''
Here is the answer you asked for.
summary: Deliveries were late.
- POINT: Order A184 arrived late.
POINT: one fact
MISSING: none
```
''';

    final parsed = LabeledSummaryParser.parse(raw);

    expect(parsed?['summary'], 'Deliveries were late.');
    expect(parsed?['keyPoints'], ['Order A184 arrived late.']);
    expect(parsed?['missingOrUnclear'], isEmpty);
    expect(parsed?['mainComplaint'], '');
  });

  test('keeps the first value when a single-value label repeats', () {
    const raw = '''
SUMMARY: First half.
SUMMARY: Second half.
COMPLAINT: Late delivery.
COMPLAINT: Something else.
''';

    final parsed = LabeledSummaryParser.parse(raw);

    expect(parsed?['summary'], 'First half. Second half.');
    expect(parsed?['mainComplaint'], 'Late delivery.');
  });

  test('reads the single point the device reply carried', () {
    // Exact reply from the device log: one POINT line, its own commentary
    // appended, and no other label.
    const raw =
        '\nPOINT: The tracking screen showed "5 minutes away" from 18:40 '
        'delivery. This indicates that the delivery time was delayed by 5 '
        'minutes, which is a significant issue for customers who rely on '
        'timely delivery.';

    final parsed = LabeledSummaryParser.parse(raw);

    expect(parsed, isNotNull);
    expect(parsed?['keyPoints'], hasLength(1));
    expect(
      (parsed?['keyPoints'] as List).single,
      startsWith('The tracking screen showed "5 minutes away"'),
    );
  });

  test('splits labels that share one line', () {
    const raw =
        'SUMMARY: Three orders had problems. POINT 1: Order A184 arrived at '
        '19:35. POINT 2: Milk was substituted. COMPLAINT: A disabled '
        'substitution was delivered. IMPROVEMENT: Block substitutions when '
        'the setting is off.';

    final parsed = LabeledSummaryParser.parse(raw);

    expect(parsed?['summary'], 'Three orders had problems.');
    expect(parsed?['keyPoints'], [
      'Order A184 arrived at 19:35.',
      'Milk was substituted.',
    ]);
    expect(parsed?['mainComplaint'], 'A disabled substitution was delivered.');
    expect(
      parsed?['suggestedImprovement'],
      'Block substitutions when the setting is off.',
    );
  });

  test('returns null without a summary or any point', () {
    expect(LabeledSummaryParser.parse(''), isNull);
    expect(LabeledSummaryParser.parse('COMPLAINT: Late delivery.'), isNull);
    expect(LabeledSummaryParser.parse('{"summary":"json"}'), isNull);
  });
}
