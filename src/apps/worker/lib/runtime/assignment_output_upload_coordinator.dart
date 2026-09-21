/// Tracks assignment output upload attempts without blocking transient retries.
enum AssignmentOutputUploadStatus {
  none,
  inFlight,
  accepted,
  rejectedTerminal,
}

class AssignmentOutputUploadCoordinator {
  AssignmentOutputUploadCoordinator({
    this.maxAttempts = 3,
    this.initialBackoff = const Duration(milliseconds: 500),
    this.maxTrackedAssignments = 32,
  });

  final int maxAttempts;
  final Duration initialBackoff;
  final int maxTrackedAssignments;

  final Map<String, AssignmentOutputUploadStatus> _statusByAssignment = {};

  AssignmentOutputUploadStatus statusFor(String assignmentId) =>
      _statusByAssignment[assignmentId] ?? AssignmentOutputUploadStatus.none;

  bool shouldSkipUpload(String assignmentId) {
    final status = statusFor(assignmentId);
    return status == AssignmentOutputUploadStatus.accepted ||
        status == AssignmentOutputUploadStatus.rejectedTerminal ||
        status == AssignmentOutputUploadStatus.inFlight;
  }

  bool markInFlight(String assignmentId) {
    if (shouldSkipUpload(assignmentId)) {
      return false;
    }
    _statusByAssignment[assignmentId] = AssignmentOutputUploadStatus.inFlight;
    _pruneIfNeeded();
    return true;
  }

  void markAccepted(String assignmentId) {
    _statusByAssignment[assignmentId] = AssignmentOutputUploadStatus.accepted;
    _pruneIfNeeded();
  }

  void markRejectedTerminal(String assignmentId) {
    _statusByAssignment[assignmentId] =
        AssignmentOutputUploadStatus.rejectedTerminal;
    _pruneIfNeeded();
  }

  void releaseInFlight(String assignmentId) {
    if (statusFor(assignmentId) == AssignmentOutputUploadStatus.inFlight) {
      _statusByAssignment.remove(assignmentId);
    }
    _pruneIfNeeded();
  }

  bool isRetryableHttpStatus(int statusCode) =>
      statusCode == 503 || statusCode >= 500;

  bool isTerminalHttpStatus(int statusCode) => statusCode == 422;

  Duration backoffForAttempt(int attempt) {
    final multiplier = 1 << attempt.clamp(0, 4);
    return Duration(
      milliseconds: initialBackoff.inMilliseconds * multiplier,
    );
  }

  void _pruneIfNeeded() {
    while (_statusByAssignment.length > maxTrackedAssignments) {
      final removable = _statusByAssignment.entries.firstWhere(
        (entry) =>
            entry.value != AssignmentOutputUploadStatus.accepted &&
            entry.value != AssignmentOutputUploadStatus.rejectedTerminal,
        orElse: () => _statusByAssignment.entries.first,
      );
      _statusByAssignment.remove(removable.key);
    }
  }
}
