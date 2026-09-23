import '../summarize_task_constraints.dart';

/// Which isolated Map diagnostic source to run (not production prompts).
enum SummarizeMapEvidenceDiagnosticFixtureId {
  /// Original fact-like lines (baseline for presentation comparison).
  baselineFactLines,

  /// Same facts as a short narrative paragraph flow.
  narrative,
}

extension SummarizeMapEvidenceDiagnosticFixtureIdLabels
    on SummarizeMapEvidenceDiagnosticFixtureId {
  String get logLabel => switch (this) {
        SummarizeMapEvidenceDiagnosticFixtureId.baselineFactLines =>
          'baseline_fact_lines',
        SummarizeMapEvidenceDiagnosticFixtureId.narrative => 'narrative',
      };

  String get uiLabel => switch (this) {
        SummarizeMapEvidenceDiagnosticFixtureId.baselineFactLines =>
          'Baseline (fact-like lines)',
        SummarizeMapEvidenceDiagnosticFixtureId.narrative =>
          'Narrative (same facts)',
      };
}

/// Baseline diagnostic source — fact-like lines (dceeebb0 plan).
const summarizeMapEvidenceDiagnosticSourceBaseline = '''
Order R201 arrived 20 minutes after its delivery window.
Order R202 contained regular milk instead of the lactose-free milk ordered,
although substitutions were disabled. Support said the customer approved
the substitution; the customer denied approval, and no approval record
was provided.
For R203, one \$72.40 payment completed. A separate pending authorization
for \$72.40 later disappeared without becoming another charge.
Support promised a \$6 refund for R202 within five business days. The
customer received it on the fourth business day.
The customer declined a \$10 coupon because it required a \$50 minimum purchase.
The customer's main concern is the disabled substitution preference being
ignored and the unsupported approval claim. The cause remains unexplained.''';

/// Narrative presentation of the same R201–R203 facts (presentation comparison).
const summarizeMapEvidenceDiagnosticSourceNarrative =
    'I am contacting you about three orders. R201 arrived 20 minutes after its '
    'delivery window. For R202, I ordered lactose-free milk but received regular '
    'milk even though substitutions were disabled. Support said I approved that '
    'change. I denied approving it, and they provided no approval record. '
    'Support promised a \$6 refund for R202 within five business days; I received '
    'it on the fourth business day. They also offered a \$10 coupon, which I '
    'declined because it required a \$50 minimum purchase. For R203, my account '
    'showed one completed \$72.40 payment and a separate pending authorization '
    'for \$72.40. That authorization later disappeared without becoming another '
    'charge. My main concern is that my disabled-substitution preference was '
    'ignored and support claimed I approved the change without showing a '
    'record. The cause remains unexplained.';

/// @deprecated Use [sourceForMapEvidenceDiagnosticFixture] with baseline id.
const summarizeMapEvidenceDiagnosticSource =
    summarizeMapEvidenceDiagnosticSourceBaseline;

String sourceForMapEvidenceDiagnosticFixture(
  SummarizeMapEvidenceDiagnosticFixtureId fixture,
) =>
    switch (fixture) {
      SummarizeMapEvidenceDiagnosticFixtureId.baselineFactLines =>
        summarizeMapEvidenceDiagnosticSourceBaseline,
      SummarizeMapEvidenceDiagnosticFixtureId.narrative =>
        summarizeMapEvidenceDiagnosticSourceNarrative,
    };

/// Same instruction block as live structured summarize tasks (100 words / 4 key points).
const summarizeMapEvidenceDiagnosticInstructions =
    'Summarize this customer case using only the supplied text. Later explicit '
    'updates supersede earlier uncertainty about the same event.\n\n'
    'Return:\n'
    '- summary: No more than 100 words.\n'
    '- keyPoints: Exactly 4 points covering delivery, the product substitution, '
    'final payment/refund status, and the coupon decision.\n'
    '- mainComplaint: The concern the customer explicitly prioritizes at the end.\n'
    '- suggestedImprovement: One practical action addressing that concern.\n'
    '- missingOrUnclear: Only questions still unresolved at the end.\n\n'
    'Preserve relevant amounts and distinguish pending authorizations, completed '
    'payments, promised refunds, and received refunds. Do not present resolved '
    'questions as still unresolved.';

SummarizeTaskConstraintsV1 summarizeMapEvidenceDiagnosticConstraints() =>
    SummarizeTaskConstraintsV1.fromJson(const {
      'schemaVersion': '1',
      'maxSummaryWords': 100,
      'keyPointCount': 4,
      'coverageAxes': [
        'delivery',
        'substitution',
        'payment_refund',
        'coupon',
      ],
      'billingRules': [
        'pending_not_confirmed_charge',
        'promised_not_completed_refund',
      ],
    });
