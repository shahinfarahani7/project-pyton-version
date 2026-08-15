import 'dart:typed_data';

class WorkerTaskInput {
  const WorkerTaskInput({
    this.imageBytes,
    this.text,
    this.imageUri,
  });

  final Uint8List? imageBytes;
  final String? text;
  final String? imageUri;

  bool get hasImage => imageBytes != null && imageBytes!.isNotEmpty;
  bool get hasText => text != null && text!.trim().isNotEmpty;
}

class WorkerTaskOptions {
  const WorkerTaskOptions({
    this.languages = const ['fa', 'en'],
    this.minOcrConfidence = 0.55,
    this.maxOutputTokens = 256,
    this.outputSchema,
    this.allowedLabels,
    this.ocrOnly = false,
  });

  final List<String> languages;
  final double minOcrConfidence;
  final int maxOutputTokens;
  final Map<String, dynamic>? outputSchema;
  final List<String>? allowedLabels;
  final bool ocrOnly;

  factory WorkerTaskOptions.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const WorkerTaskOptions();
    }
    return WorkerTaskOptions(
      languages: (json['languages'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['fa', 'en'],
      minOcrConfidence: (json['minOcrConfidence'] as num?)?.toDouble() ?? 0.55,
      maxOutputTokens: (json['maxOutputTokens'] as num?)?.toInt() ?? 256,
      outputSchema: json['outputSchema'] as Map<String, dynamic>?,
      allowedLabels: (json['allowedLabels'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      ocrOnly: json['ocrOnly'] == true,
    );
  }
}

class WorkerTaskRequest {
  const WorkerTaskRequest({
    required this.schemaVersion,
    required this.taskId,
    required this.idempotencyKey,
    required this.type,
    required this.input,
    this.options = const WorkerTaskOptions(),
    this.deadlineAt,
    this.createdAt,
  });

  final String schemaVersion;
  final String taskId;
  final String idempotencyKey;
  final String type;
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
