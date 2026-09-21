/// Server-authorized hierarchical reduce bounds (Architecture v2 §26).
class HierarchicalReduceBounds {
  const HierarchicalReduceBounds({
    this.maxChunks = 64,
    this.maxReduceDepth = 8,
    this.maxInferenceCalls = 128,
    this.maxOutputTokensPerStage = 300,
    this.minTokenMassReductionRatioMilli = 50,
  });

  static const textSummarizeMapReduce = HierarchicalReduceBounds();

  /// Soft per-chunk map preference; final [SummarizeTaskConstraintsV1.keyPointCount]
  /// is enforced only after reduce/direct validation.
  static const mapIntermediateMaxKeyPoints = 3;

  final int maxChunks;
  final int maxReduceDepth;
  final int maxInferenceCalls;
  final int maxOutputTokensPerStage;
  final int minTokenMassReductionRatioMilli;
}

class ReduceProgressTracker {
  ReduceProgressTracker({required this.bounds});

  final HierarchicalReduceBounds bounds;
  int inferenceCalls = 0;
  int maxDepthObserved = 0;

  void recordDepth(int depth) {
    if (depth > maxDepthObserved) {
      maxDepthObserved = depth;
    }
    if (depth >= bounds.maxReduceDepth) {
      throw HierarchicalReduceExhaustedException(
        reason: 'max_reduce_depth_exceeded',
        depth: depth,
        inferenceCalls: inferenceCalls,
      );
    }
  }

  void recordInferenceCall() {
    inferenceCalls += 1;
    if (inferenceCalls > bounds.maxInferenceCalls) {
      throw HierarchicalReduceExhaustedException(
        reason: 'max_inference_calls_exceeded',
        depth: maxDepthObserved,
        inferenceCalls: inferenceCalls,
      );
    }
  }

  void assertChunkCount(int chunkCount) {
    if (chunkCount > bounds.maxChunks) {
      throw HierarchicalReduceExhaustedException(
        reason: 'chunk_cap_exceeded',
        depth: maxDepthObserved,
        inferenceCalls: inferenceCalls,
        chunkCount: chunkCount,
      );
    }
  }
}

class HierarchicalReduceExhaustedException implements Exception {
  HierarchicalReduceExhaustedException({
    required this.reason,
    required this.depth,
    required this.inferenceCalls,
    this.chunkCount,
  });

  final String reason;
  final int depth;
  final int inferenceCalls;
  final int? chunkCount;

  @override
  String toString() =>
      'HierarchicalReduceExhaustedException('
      'reason=$reason, depth=$depth, inferenceCalls=$inferenceCalls'
      '${chunkCount != null ? ', chunkCount=$chunkCount' : ''})';
}
