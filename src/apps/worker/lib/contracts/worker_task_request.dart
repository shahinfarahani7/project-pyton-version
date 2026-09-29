import 'dart:typed_data';

import '../inference/llm/summarize_task_constraints.dart';

class WorkerTaskInput {
  const WorkerTaskInput({
    this.imageBytes,
    this.compareImageBytes,
    this.text,
    this.imageUri,
    this.data = const {},
  });

  final Uint8List? imageBytes;
  final Uint8List? compareImageBytes;
  final String? text;
  final String? imageUri;

  /// Canonical structured payload for Flex and paired-text contracts.
  final Map<String, dynamic> data;

  bool get hasImage => imageBytes != null && imageBytes!.isNotEmpty;
  bool get hasCompareImage =>
      compareImageBytes != null && compareImageBytes!.isNotEmpty;
  bool get hasText => text != null && text!.trim().isNotEmpty;
}

class WorkerTaskOptions {
  const WorkerTaskOptions({
    this.languages = const ['fa', 'en'],
    this.minOcrConfidence = 0.55,
    this.maxOutputTokens = 256,
    this.maxOutputTokensSpecified = false,
    this.longForm = false,
    this.allowTruncatedOutput = false,
    this.outputSchema,
    this.allowedLabels,
    this.ocrOnly = false,
    this.summarize,
  });

  final List<String> languages;
  final double minOcrConfidence;
  final int maxOutputTokens;

  /// True only when the task payload set `maxOutputTokens` explicitly.
  final bool maxOutputTokensSpecified;

  /// Asks `text.direct` to use the long-form output budget.
  final bool longForm;

  /// When false, a structured task that hits the output cap fails.
  /// Free-form text.direct still returns the partial text with truncated=true.
  final bool allowTruncatedOutput;
  final Map<String, dynamic>? outputSchema;
  final List<String>? allowedLabels;
  final bool ocrOnly;
  final SummarizeTaskConstraintsV1? summarize;

  factory WorkerTaskOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const WorkerTaskOptions();
    }
    SummarizeTaskConstraintsV1? summarize;
    final summarizeRaw = json['summarize'];
    if (summarizeRaw is Map<String, dynamic>) {
      summarize = SummarizeTaskConstraints.parseOptionsMap(summarizeRaw);
    }
    return WorkerTaskOptions(
      languages:
          (json['languages'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['fa', 'en'],
      minOcrConfidence: (json['minOcrConfidence'] as num?)?.toDouble() ?? 0.55,
      maxOutputTokens: (json['maxOutputTokens'] as num?)?.toInt() ?? 256,
      maxOutputTokensSpecified: json.containsKey('maxOutputTokens'),
      longForm: json['longForm'] == true,
      allowTruncatedOutput: json['allowTruncatedOutput'] == true,
      outputSchema: json['outputSchema'] as Map<String, dynamic>?,
      allowedLabels: (json['allowedLabels'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      ocrOnly: json['ocrOnly'] == true,
      summarize: summarize,
    );
  }
}

class WorkerTaskRequest {
  const WorkerTaskRequest({
    required this.schemaVersion,
    required this.taskId,
    required this.idempotencyKey,
    required this.type,
    this.sourceTaskType = '',
    required this.input,
    this.options = const WorkerTaskOptions(),
    this.deadlineAt,
    this.createdAt,
  });

  final String schemaVersion;
  final String taskId;
  final String idempotencyKey;
  final String type;

  /// Backend catalog type, preserved after routing to an internal capability.
  final String sourceTaskType;
  final WorkerTaskInput input;
  final WorkerTaskOptions options;
  final DateTime? deadlineAt;
  final DateTime? createdAt;

  bool get isExpired {
    final deadline = deadlineAt;
    if (deadline == null) {
      return false;
    }
    return DateTime.now().toUtc().isAfter(deadline.toUtc());
  }
}
