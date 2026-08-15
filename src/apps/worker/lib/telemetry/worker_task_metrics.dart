import '../contracts/worker_task_result.dart';

class WorkerTaskMetrics {
  WorkerTaskMetrics({DateTime? startedAt}) : _startedAt = startedAt ?? DateTime.now();

  final DateTime _startedAt;
  int queueMs = 0;
  int preprocessMs = 0;
  int ocrMs = 0;
  int llmMs = 0;
  int? inputBytes;
  int? imageWidth;
  int? imageHeight;
  double? averageOcrConfidence;
  int? peakMemoryMb;

  int get totalMs => DateTime.now().difference(_startedAt).inMilliseconds;

  Map<String, dynamic> toJson() => {
        'queueMs': queueMs,
        'preprocessMs': preprocessMs,
        'ocrMs': ocrMs,
        'llmMs': llmMs,
        'totalMs': totalMs,
        if (averageOcrConfidence != null) 'averageOcrConfidence': averageOcrConfidence,
        if (peakMemoryMb != null) 'peakMemoryMb': peakMemoryMb,
        if (inputBytes != null) 'inputBytes': inputBytes,
        if (imageWidth != null && imageHeight != null)
          'imageDimensions': '${imageWidth}x$imageHeight',
      };
}
