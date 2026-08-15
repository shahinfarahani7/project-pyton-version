import 'worker_error.dart';

class OcrLineResult {
  const OcrLineResult({
    required this.text,
    required this.confidence,
    required this.box,
    this.belowThreshold = false,
  });

  final String text;
  final double confidence;
  final List<int> box;
  final bool belowThreshold;

  Map<String, dynamic> toJson() => {
        'text': text,
        'confidence': confidence,
        'box': box,
        if (belowThreshold) 'belowThreshold': true,
      };
}

class WorkerTaskResult {
  const WorkerTaskResult({
    required this.schemaVersion,
    required this.taskId,
    required this.status,
    this.output,
    this.metrics = const {},
    this.modelInfo = const {},
    this.error,
  });

  final String schemaVersion;
  final String taskId;
  final WorkerResultStatus status;
  final Map<String, dynamic>? output;
  final Map<String, dynamic> metrics;
  final Map<String, dynamic> modelInfo;
  final WorkerError? error;

  String get resultTextPreview {
    if (output == null) {
      return error?.message ?? status.name;
    }
    final data = output!['data'];
    if (data is Map<String, dynamic>) {
      return data.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    }
    final summary = output!['summary'];
    if (summary is String) {
      return summary;
    }
    final raw = output!['rawText'];
    if (raw is String) {
      return raw;
    }
    return output.toString();
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'taskId': taskId,
        'status': status.name.toUpperCase(),
        'output': output,
        'metrics': metrics,
        'modelInfo': modelInfo,
        'error': error?.toJson(),
      };
}
