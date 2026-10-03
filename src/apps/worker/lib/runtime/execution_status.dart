enum ServerSyncState { idle, pending, unknownOutcome }

enum ExecutionPhase {
  idle,
  waitingForAssignment,
  preparing,
  running,
  checkpointing,
  submitting,
  cleaningUp,
  paused,
  failed,
  completed,
}

class ExecutionStatus {
  const ExecutionStatus({
    required this.phase,
    this.assignmentId,
    this.taskId,
    this.taskType,
    this.progressMilli = 0,
    this.detail,
    this.visibleToUser = true,
    this.serverSync = ServerSyncState.idle,
  });

  final ExecutionPhase phase;
  final String? assignmentId;
  final String? taskId;
  final String? taskType;
  final int progressMilli;
  final String? detail;
  final bool visibleToUser;
  final ServerSyncState serverSync;

  ExecutionStatus copyWith({
    ExecutionPhase? phase,
    String? assignmentId,
    String? taskId,
    String? taskType,
    int? progressMilli,
    String? detail,
    bool? visibleToUser,
    ServerSyncState? serverSync,
  }) {
    return ExecutionStatus(
      phase: phase ?? this.phase,
      assignmentId: assignmentId ?? this.assignmentId,
      taskId: taskId ?? this.taskId,
      taskType: taskType ?? this.taskType,
      progressMilli: progressMilli ?? this.progressMilli,
      detail: detail ?? this.detail,
      visibleToUser: visibleToUser ?? this.visibleToUser,
      serverSync: serverSync ?? this.serverSync,
    );
  }
}
