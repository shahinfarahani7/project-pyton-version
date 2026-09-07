import 'dart:convert';

import 'context_budget_manager.dart';

/// Validates semantic merge progress during hierarchical reduce (v2 §26).
abstract final class SemanticMergeValidator {
  static int estimateTokenMass(Object payload) {
    final encoded = jsonEncode(payload);
    if (encoded.isEmpty) {
      return 0;
    }
    return (encoded.length / 4).ceil().clamp(1, 1 << 30);
  }

  static int estimatePartialsTokenMass(List<Map<String, dynamic>> partials) =>
      estimateTokenMass(partials);

  static bool madeProgress({
    required int beforeGroups,
    required int afterGroups,
    required int beforeTokenMass,
    required int afterTokenMass,
    required int minTokenMassReductionRatioMilli,
  }) {
    if (afterGroups < beforeGroups) {
      return true;
    }
    if (afterTokenMass >= beforeTokenMass) {
      return false;
    }
    if (beforeTokenMass <= 0) {
      return afterTokenMass < beforeTokenMass;
    }
    final reductionMilli =
        ((beforeTokenMass - afterTokenMass) * 1000) ~/ beforeTokenMass;
    return reductionMilli >= minTokenMassReductionRatioMilli;
  }

  static void assertDirectReduceProgress({
    required List<Map<String, dynamic>> inputPartials,
    required Map<String, dynamic> output,
    required int minTokenMassReductionRatioMilli,
  }) {
    if (inputPartials.length <= 1) {
      return;
    }
    final beforeMass = estimatePartialsTokenMass(inputPartials);
    final afterMass = estimateTokenMass(output);
    if (!madeProgress(
      beforeGroups: inputPartials.length,
      afterGroups: 1,
      beforeTokenMass: beforeMass,
      afterTokenMass: afterMass,
      minTokenMassReductionRatioMilli: minTokenMassReductionRatioMilli,
    )) {
      throw SemanticMergeNoProgressException(
        beforeGroups: inputPartials.length,
        afterGroups: 1,
        beforeTokenMass: beforeMass,
        afterTokenMass: afterMass,
      );
    }
  }
}

class SemanticMergeNoProgressException implements Exception {
  SemanticMergeNoProgressException({
    required this.beforeGroups,
    required this.afterGroups,
    required this.beforeTokenMass,
    required this.afterTokenMass,
  });

  final int beforeGroups;
  final int afterGroups;
  final int beforeTokenMass;
  final int afterTokenMass;

  @override
  String toString() =>
      'SemanticMergeNoProgressException('
      'groups=$beforeGroups->$afterGroups, '
      'tokenMass=$beforeTokenMass->$afterTokenMass)';
}
