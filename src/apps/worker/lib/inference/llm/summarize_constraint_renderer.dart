import 'summarize_task_constraints.dart';

/// Renders structured constraints for model prompts (informational + enforced).
abstract final class SummarizeConstraintRenderer {
  static const _billingRuleDescriptions = {
    'pending_not_confirmed_charge':
        'Do not describe a pending bank authorization as a confirmed charge.',
    'promised_not_completed_refund':
        'Do not describe a promised refund as already completed.',
  };

  static String promptBlock(SummarizeTaskConstraintsV1? constraints) {
    if (constraints == null) {
      return '';
    }
    final lines = <String>[
      'Structured output requirements from the task definition:',
    ];
    if (constraints.maxSummaryWords != null) {
      lines.add(
        '- summary: at most ${constraints.maxSummaryWords} words (enforced).',
      );
    }
    if (constraints.keyPointCount != null) {
      lines.add(
        '- keyPoints: exactly ${constraints.keyPointCount} distinct facts '
        '(enforced).',
      );
    }
    if (constraints.coverageAxes.isNotEmpty) {
      lines.add(
        '- keyPoints should cover these topics where the source mentions them: '
        '${constraints.coverageAxes.join(", ")} (informational; not '
        'automatically validated).',
      );
    }
    if (constraints.billingRules.isNotEmpty) {
      lines.add('- Preserve these billing distinctions in wording:');
      for (final ruleId in constraints.billingRules) {
        final description =
            _billingRuleDescriptions[ruleId] ?? 'Follow rule $ruleId.';
        lines.add('  - $ruleId: $description (informational; not '
            'automatically validated).');
      }
    }
    return '${lines.join("\n")}\n';
  }
}
