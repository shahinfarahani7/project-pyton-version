import 'package:edgemint_worker/inference/llm/summarize_output_validator.dart';
import 'package:edgemint_worker/inference/llm/summarize_task_constraints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final constraints = SummarizeTaskConstraintsV1.fromJson(const {
    'schemaVersion': '1',
    'maxSummaryWords': 80,
    'keyPointCount': 5,
    'coverageAxes': ['delivery', 'tracking', 'billing'],
    'billingRules': ['pending_not_confirmed_charge'],
  });

  Map<String, dynamic> validSummary() => {
    'summary': 'Customer reported delivery, tracking, billing, and support issues.',
    'keyPoints': [
      'Order A184 arrived late.',
      'Tracking showed five minutes away for an hour.',
      'Order A219 had an unauthorized substitution.',
      'Order A237 has a pending authorization for \$64.80.',
      'Support promised a \$12 refund within five business days.',
    ],
    'mainComplaint': 'Unauthorized dietary substitution.',
    'suggestedImprovement': 'Audit substitution approvals.',
    'missingOrUnclear': ['Whether pending authorization becomes a charge.'],
  };

  test('does not reject valid paraphrases without keyword heuristics', () {
    final result = SummarizeOutputValidator.validate(
      summary: {
        ...validSummary(),
        'keyPoints': [
          'One completed payment plus another pending authorization for \$64.80.',
          'Tracking estimates were unreliable for order A184.',
          'Substitution settings were disabled but regular milk arrived.',
          'Support offered a coupon the customer declined.',
          'Order A237 arrived after conflicting support messages.',
        ],
      },
      constraints: constraints,
    );

    expect(result.passed, isTrue);
  });

  test('reports coverage axes and billing rules as unchecked', () {
    final result = SummarizeOutputValidator.validate(
      summary: validSummary(),
      constraints: constraints,
    );

    expect(result.passed, isTrue);
    expect(result.uncheckedCoverageAxes, contains('delivery'));
    expect(result.uncheckedBillingRuleIds, contains('pending_not_confirmed_charge'));
  });

  test('blocks wrong keyPoint count and word limit', () {
    final tooManyWords = List.filled(90, 'word').join(' ');
    final result = SummarizeOutputValidator.validate(
      summary: {
        ...validSummary(),
        'summary': tooManyWords,
        'keyPoints': ['one', 'two', 'three'],
      },
      constraints: constraints,
    );

    expect(result.passed, isFalse);
    expect(
      result.blockingViolations.join(' '),
      contains('maxSummaryWords'),
    );
    expect(
      result.blockingViolations.join(' '),
      contains('keyPoints count'),
    );
  });

  test('distinguishes unknown billing rule ids at parse time', () {
    expect(
      () => SummarizeTaskConstraints.parseOptionsMap(const {
        'schemaVersion': '1',
        'billingRules': ['unknown_rule_id'],
      }),
      throwsA(isA<SummarizeConstraintsException>()),
    );
  });
}
