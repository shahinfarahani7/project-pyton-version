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
    this.taskType,
    this.progressMilli = 0,
    this.detail,
    this.visibleToUser = true,
  });

  final ExecutionPhase phase;
  final String? assignmentId;
  final String? taskType;
  final int progressMilli;
  final String? detail;
  final bool visibleToUser;

  ExecutionStatus copyWith({
    ExecutionPhase? phase,
    String? assignmentId,
    String? taskType,
    int? progressMilli,
    String? detail,
    bool? visibleToUser,
  }) {
    return ExecutionStatus(
      phase: phase ?? this.phase,
      assignmentId: assignmentId ?? this.assignmentId,
      taskType: taskType ?? this.taskType,
      progressMilli: progressMilli ?? this.progressMilli,
      detail: detail ?? this.detail,
      visibleToUser: visibleToUser ?? this.visibleToUser,
    );
  }
}
