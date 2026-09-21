import 'package:edgemint_worker/inference/llm/summarize_task_constraints.dart';

/// Regression fixture from the grocery customer-feedback task (Sep 2026).
const customerFeedbackInstructions =
    'Analyze the customer feedback using only the provided content.\n\n'
    'Return:\n'
    '- summary: A summary of no more than 80 words.\n'
    '- keyPoints: Exactly 5 distinct facts covering delivery, tracking, '
    'product issues, billing, and support.\n'
    '- mainComplaint: The customer\'s main complaint, respecting their '
    'stated priority.\n'
    '- suggestedImprovement: One practical action addressing the main '
    'complaint.\n'
    '- missingOrUnclear: Information that is genuinely missing or unresolved.\n\n'
    'Preserve numbers and distinguish confirmed facts from claims and promises. '
    'Do not describe a pending bank authorization as a confirmed charge. '
    'Do not describe a promised refund as completed.';

const customerFeedbackSource =
    'I have used this grocery delivery service for six months. My first eight '
    'orders arrived on time, but the most recent three had problems.\n\n'
    'On September 3, order A184 was scheduled for 18:00–19:00 and arrived at '
    '19:35. The tracking screen showed “5 minutes away” from 18:40 until '
    'delivery. Two yogurts arrived warm. I discarded them, but I did not '
    'measure their temperature.\n\n'
    'On September 7, order A219 arrived within its promised delivery window. '
    'However, I received regular milk instead of the lactose-free milk I '
    'ordered. My account settings show that substitutions are disabled. The '
    'receipt lists lactose-free milk, while the photo I sent support shows '
    'regular milk. Support said I had approved the substitution, but they did '
    'not provide a record of that approval.\n\n'
    'On September 12, order A237 was due between 17:00 and 18:00. At 18:20, '
    'support said the driver was nearby. At 18:45, another agent said the '
    'order had not left the store. It arrived at 19:10, with all items '
    'correct.\n\n'
    'For order A237, my banking app shows one completed payment of \$64.80 and '
    'a second pending authorization for \$64.80. I do not know whether the '
    'pending amount will disappear or become another charge.\n\n'
    'Support promised a \$12 refund for the incorrect milk and discarded '
    'yogurts within five business days. Only two business days have passed, '
    'and I have not received it yet. They also offered a \$10 coupon, which I '
    'declined because it required a \$50 minimum purchase.\n\n'
    'The app is easy to use, and the drivers have been polite. Late deliveries '
    'are frustrating, but my main concern is receiving a dietary substitution '
    'I explicitly disabled and then being told I approved it. I want the '
    'company to investigate how that happened and prevent it from happening '
    'again. I have not decided whether to stop using the service.';

SummarizeTaskConstraintsV1 customerFeedbackConstraints() =>
    SummarizeTaskConstraintsV1.fromJson(const {
      'schemaVersion': '1',
      'maxSummaryWords': 80,
      'keyPointCount': 5,
      'coverageAxes': [
        'delivery',
        'tracking',
        'product',
        'billing',
        'support',
      ],
      'billingRules': [
        'pending_not_confirmed_charge',
        'promised_not_completed_refund',
      ],
    });

/// Tail of [customerFeedbackInstructions] that was previously truncated at 600 chars.
const customerFeedbackInstructionTailMarker =
    'Do not describe a promised refund as completed.';
