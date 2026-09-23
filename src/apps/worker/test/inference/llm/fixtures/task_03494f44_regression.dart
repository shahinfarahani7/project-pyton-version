import 'package:edgemint_worker/inference/llm/summarize_task_constraints.dart';

/// Live regression task (supplied log evidence; e.g. tsk_dev_01a0f237).
///
/// Worker manifest must include explicit `options.summarize` matching
/// [task03494f44Constraints] (portal: enable "Phase 1 regression structured
/// options" on text.summarize create, or pass summarizeOptions in API).
const task03494f44ObservedInputChars = 13769;
const task03494f44ObservedInputSha256 =
    '066ad7525cf932b844c1e6c90a8fd68bd73b0785c8dea92edb66351d450daba7';

/// Verbatim `instructions` field from the live manifest (user note only).
const task03494f44Instructions =
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

SummarizeTaskConstraintsV1 task03494f44Constraints() =>
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
