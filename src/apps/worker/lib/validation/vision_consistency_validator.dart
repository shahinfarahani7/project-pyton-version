import '../contracts/worker_error.dart';

/// Rejects schema-valid but internally contradictory visual decisions.
abstract final class VisionConsistencyValidator {
  static WorkerError? validate(String taskType, Map<String, dynamic> data) {
    final risk = data['riskScore'];
    if (risk is num && (risk < 0 || risk > 1))
      return _error('riskScore must be in [0,1]');
    final confidence = data['confidence'];
    if (confidence is num && (confidence < 0 || confidence > 1))
      return _error('confidence must be in [0,1]');
    if (taskType == 'catalog.product_quality_score') {
      final score = data['score'];
      if (score is! num || score < 0 || score > 1)
        return _error('quality score must be in [0,1]');
    }
    final positive = switch (taskType) {
      'safety.nsfw_detection' => data['nsfw'] == true,
      'safety.violence_detection' => data['violence'] == true,
      'safety.weapon_detection' => data['weapon'] == true,
      'catalog.prohibited_product' => data['prohibited'] == true,
      'safety.unsafe_image' ||
      'llm.image_output_safety' => data['safe'] == false,
      _ => false,
    };
    if (positive && risk is num && risk == 0)
      return _error('positive risk decision cannot have zero riskScore');
    final reason = data['reason']?.toString().toLowerCase() ?? '';
    for (final value in data.values) {
      if (value is List &&
          value.any((item) => item.toString().toLowerCase() == 'array')) {
        return _error('schema placeholder leaked into output');
      }
    }
    if (taskType == 'safety.weapon_detection' &&
        data['weapon'] == true &&
        (reason.contains('no visible weapon') ||
            reason.contains('no weapon'))) {
      return _error('weapon decision contradicts reason');
    }
    if (taskType == 'catalog.brand_logo' && data['detected'] == true) {
      if ((data['brands'] is! List || (data['brands'] as List).isEmpty) ||
          (data['evidence'] is! List || (data['evidence'] as List).isEmpty)) {
        return _error(
          'positive brand detection requires brand and visible evidence',
        );
      }
    }
    if (taskType == 'catalog.prohibited_product' &&
        data['prohibited'] == false &&
        reason.contains('is prohibited')) {
      return _error('prohibited-product decision contradicts reason');
    }
    if ((data['allowed'] == true || data['safe'] == true) &&
        (reason.contains('not possible to definitively assess') ||
            reason.contains('cannot assess'))) {
      return _error('uncertain output cannot be marked allowed');
    }
    return null;
  }

  static WorkerError _error(String message) => WorkerError(
    code: WorkerErrorCode.outputSchemaMismatch,
    message: message,
    retryable: true,
    stage: WorkerTaskStage.llm,
  );
}
