class WorkerAssignment {
  WorkerAssignment({
    required this.assignmentId,
    required this.attemptId,
    required this.revisionId,
    required this.leaseToken,
    required this.fenceToken,
    required this.leaseExpiresAt,
    required this.taskType,
    required this.modelVersionId,
    required this.inputManifestUrl,
    required this.outputUploadUrl,
    required this.startDeadlineAt,
    this.taskId,
    this.deliveryInboxId,
    this.assignmentMode = 'auto',
    this.executionStartsAutomatically = true,
    this.executionPlan,
    this.allocation,
  });

  factory WorkerAssignment.fromJson(Map<String, dynamic> json) => WorkerAssignment(
        assignmentId: json['assignmentId'] as String,
        attemptId: json['attemptId'] as String,
        revisionId: json['revisionId'] as String,
        leaseToken: json['leaseToken'] as String,
        fenceToken: json['fenceToken'] as int,
        leaseExpiresAt: DateTime.parse(json['leaseExpiresAt'] as String),
        taskType: json['taskType'] as String,
        modelVersionId: json['modelVersionId'] as String,
        inputManifestUrl: json['inputManifestUrl'] as String,
        outputUploadUrl: json['outputUploadUrl'] as String,
        startDeadlineAt: DateTime.parse(json['startDeadlineAt'] as String),
        taskId: json['taskId'] as String?,
        deliveryInboxId: json['deliveryInboxId'] as String?,
        assignmentMode: json['assignmentMode'] as String? ?? 'auto',
        executionStartsAutomatically: json['executionStartsAutomatically'] as bool? ?? true,
        executionPlan: json['executionPlan'] as Map<String, dynamic>?,
        allocation: json['allocation'] as Map<String, dynamic>?,
      );

  final String assignmentId;
  final String attemptId;
  final String revisionId;
  final String leaseToken;
  final int fenceToken;
  final DateTime leaseExpiresAt;
  final String taskType;
  final String modelVersionId;
  final String inputManifestUrl;
  final String outputUploadUrl;
  final DateTime startDeadlineAt;
  final String? taskId;
  final String? deliveryInboxId;
  final String assignmentMode;
  final bool executionStartsAutomatically;
  final Map<String, dynamic>? executionPlan;
  final Map<String, dynamic>? allocation;
}

class CommandReceipt {
  CommandReceipt({
    required this.operationId,
    required this.accepted,
    required this.status,
    required this.occurredAt,
  });

  factory CommandReceipt.fromJson(Map<String, dynamic> json) => CommandReceipt(
        operationId: json['operationId'] as String,
        accepted: json['accepted'] as bool,
        status: json['status'] as String,
        occurredAt: DateTime.parse(json['occurredAt'] as String),
      );

  final String operationId;
  final bool accepted;
  final String status;
  final DateTime occurredAt;
}
