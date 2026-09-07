import 'package:edgemint_worker/runtime/checkpoint_store.dart';

/// Tracks assignment-scoped temporary artifacts and privacy cleanup (v2 §54, §55, A21/T21).
class PrivacyCleanupCoordinator {
  PrivacyCleanupCoordinator({
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, _AssignmentPrivacyState> _states = {};
  String? _lastCompletedAssignmentId;
  String? _activeBufferOwnerAssignmentId;

  void registerTempBlob({
    required String assignmentId,
    required String blobRef,
  }) {
    final state = _states.putIfAbsent(assignmentId, _AssignmentPrivacyState.new);
    state.tempBlobRefs.add(blobRef);
  }

  void bindActiveBuffers({required String assignmentId}) {
    _activeBufferOwnerAssignmentId = assignmentId;
  }

  void markResumeGrantActive({required String assignmentId}) {
    final state = _states.putIfAbsent(assignmentId, _AssignmentPrivacyState.new);
    state.resumeGrantActive = true;
  }

  Future<PrivacyCleanupResult> cleanupAfterAssignment({
    required String assignmentId,
    required CheckpointStore checkpointStore,
    bool preserveCheckpoint = false,
  }) async {
    final state = _states[assignmentId];
    final tempRefs = state?.tempBlobRefs.toList() ?? const <String>[];
    final removedTempRefs = <String>[];
    for (final ref in tempRefs) {
      removedTempRefs.add(ref);
    }
    state?.tempBlobRefs.clear();

    var checkpointPurged = false;
    if (!preserveCheckpoint && !(state?.resumeGrantActive ?? false)) {
      await checkpointStore.purge(assignmentId);
      checkpointPurged = true;
    }

    if (_activeBufferOwnerAssignmentId == assignmentId) {
      _activeBufferOwnerAssignmentId = null;
    }
    _lastCompletedAssignmentId = assignmentId;

    return PrivacyCleanupResult(
      assignmentId: assignmentId,
      removedTempRefs: removedTempRefs,
      checkpointPurged: checkpointPurged,
      buffersReset: _activeBufferOwnerAssignmentId == null,
      cleanedAt: _clock(),
    );
  }

  bool wouldLeakIntoNextAssignment(String nextAssignmentId) {
    if (_activeBufferOwnerAssignmentId == null) {
      return false;
    }
    return _activeBufferOwnerAssignmentId != nextAssignmentId;
  }

  String? get lastCompletedAssignmentId => _lastCompletedAssignmentId;
}

class PrivacyCleanupResult {
  const PrivacyCleanupResult({
    required this.assignmentId,
    required this.removedTempRefs,
    required this.checkpointPurged,
    required this.buffersReset,
    required this.cleanedAt,
  });

  final String assignmentId;
  final List<String> removedTempRefs;
  final bool checkpointPurged;
  final bool buffersReset;
  final DateTime cleanedAt;
}

class _AssignmentPrivacyState {
  final Set<String> tempBlobRefs = {};
  bool resumeGrantActive = false;
}
