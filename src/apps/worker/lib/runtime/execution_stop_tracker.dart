/// Tracks stop requested vs stop confirmed for bounded grant cleanup (v2 §47).
class ExecutionStopTracker {
  ExecutionStopTracker({
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  DateTime? _stopRequestedAt;
  DateTime? _stopConfirmedAt;
  String? _proof;

  DateTime? get stopRequestedAt => _stopRequestedAt;
  DateTime? get stopConfirmedAt => _stopConfirmedAt;
  String? get proof => _proof;

  bool get isStopConfirmed => _stopConfirmedAt != null;

  void requestStop({String reason = 'lease_expired_or_abort'}) {
    _stopRequestedAt ??= _clock();
  }

  void confirmStop({required String proof}) {
    _stopRequestedAt ??= _clock();
    _stopConfirmedAt = _clock();
    _proof = proof;
  }

  Map<String, Object?> toTelemetry() => {
        'stopRequestedAt': _stopRequestedAt?.toIso8601String(),
        'stopConfirmedAt': _stopConfirmedAt?.toIso8601String(),
        if (_proof != null) 'physicalReleaseProof': _proof,
      };

  void reset() {
    _stopRequestedAt = null;
    _stopConfirmedAt = null;
    _proof = null;
  }
}

String buildPhysicalReleaseProof({
  required String assignmentId,
  required int fenceToken,
  required String cleanupPhase,
}) {
  return '$assignmentId|$fenceToken|$cleanupPhase|stop_confirmed';
}
