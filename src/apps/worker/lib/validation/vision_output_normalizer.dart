import '../contracts/task_contract_catalog.dart';

/// Conservative deterministic fallback after VLM and bounded Qwen repair.
abstract final class VisionOutputNormalizer {
  static Map<String, dynamic> normalize(
    String taskType,
    Map<String, dynamic>? source,
  ) {
    final schema = TaskContractCatalog.forType(taskType)!.outputSchema;
    final data = <String, dynamic>{...?source};
    for (final entry in schema.entries) {
      data.putIfAbsent(entry.key, () => _defaultValue(entry.value.toString()));
    }
    for (final key in const ['confidence', 'riskScore']) {
      final value = data[key];
      if (value is num) data[key] = value.clamp(0, 1).toDouble();
    }
    if (taskType == 'catalog.product_quality_score' && data['score'] is num) {
      data['score'] = (data['score'] as num).clamp(0, 1).toDouble();
    }
    final positiveRisk = switch (taskType) {
      'safety.nsfw_detection' => data['nsfw'] == true,
      'safety.violence_detection' => data['violence'] == true,
      'safety.weapon_detection' => data['weapon'] == true,
      'catalog.prohibited_product' => data['prohibited'] == true,
      'safety.unsafe_image' ||
      'llm.image_output_safety' => data['safe'] == false,
      _ => false,
    };
    if (positiveRisk && data['riskScore'] == 0.0) data['riskScore'] = 1.0;
    final reason = data['reason']?.toString().toLowerCase() ?? '';
    if (taskType == 'safety.weapon_detection' &&
        data['weapon'] == true &&
        (reason.contains('no visible weapon') ||
            reason.contains('no weapon'))) {
      data['reason'] = 'Ambiguous weapon signal; conservative review required';
      data['riskScore'] = 1.0;
    }
    if (taskType == 'catalog.brand_logo' &&
        data['detected'] == true &&
        ((data['brands'] as List).isEmpty ||
            (data['evidence'] as List).isEmpty)) {
      data
        ..['detected'] = false
        ..['brands'] = <dynamic>[]
        ..['confidence'] = 0.0
        ..['evidence'] = <dynamic>[];
    }
    for (final entry in data.entries.toList()) {
      if (entry.value is List) {
        data[entry.key] = (entry.value as List)
            .where((item) => item.toString().toLowerCase() != 'array')
            .toList();
      }
    }
    if (taskType == 'catalog.prohibited_product' &&
        data['prohibited'] == false &&
        reason.contains('is prohibited')) {
      data['prohibited'] = true;
      data['riskScore'] = 1.0;
    }
    if ((data['allowed'] == true || data['safe'] == true) &&
        (reason.contains('not possible to definitively assess') ||
            reason.contains('cannot assess'))) {
      if (data.containsKey('allowed')) data['allowed'] = false;
      if (data.containsKey('safe')) data['safe'] = false;
      if (data.containsKey('riskScore')) data['riskScore'] = 1.0;
      data['needsHumanReview'] = true;
    }
    return data;
  }

  static Map<String, dynamic> fallback(String taskType) {
    final data = normalize(taskType, null);
    switch (taskType) {
      case 'safety.nsfw_detection':
        data['nsfw'] = true;
        break;
      case 'safety.violence_detection':
        data['violence'] = true;
        break;
      case 'safety.weapon_detection':
        data['weapon'] = true;
        break;
      case 'safety.unsafe_image':
      case 'llm.image_output_safety':
        data['safe'] = false;
        break;
      case 'catalog.prohibited_product':
        data['prohibited'] = true;
        break;
    }
    if (data.containsKey('riskScore')) data['riskScore'] = 1.0;
    if (data.containsKey('reason'))
      data['reason'] =
          'Model output unresolved; conservative human review required';
    data['needsHumanReview'] = true;
    data['fallbackApplied'] = true;
    return data;
  }

  static dynamic _defaultValue(String expected) {
    if (expected.contains('string')) return '';
    if (expected.contains('number')) return 0.0;
    if (expected.contains('boolean')) return false;
    if (expected.contains('array')) return <dynamic>[];
    if (expected.contains('object')) return <String, dynamic>{};
    return null;
  }
}
