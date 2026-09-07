/// Authenticated ResumeGrant for cross-Assignment checkpoint resume (v2 §46).
class ResumeGrant {
  const ResumeGrant({
    required this.grantId,
    required this.assignmentId,
    required this.activeFenceToken,
    required this.inputDigest,
    required this.authorizedChunkIds,
    required this.modelVersionId,
    required this.runtimeVersion,
    required this.promptTemplateVersion,
    required this.executionPlanVersion,
    required this.producerFenceToken,
    required this.producerAssignmentId,
    required this.expiresAt,
  });

  final String grantId;
  final String assignmentId;
  final int activeFenceToken;
  final String inputDigest;
  final Set<String> authorizedChunkIds;
  final String modelVersionId;
  final String runtimeVersion;
  final String promptTemplateVersion;
  final String executionPlanVersion;
  final int producerFenceToken;
  final String producerAssignmentId;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  factory ResumeGrant.fromJson(Map<String, dynamic> json) => ResumeGrant(
        grantId: json['grantId'] as String,
        assignmentId: json['assignmentId'] as String,
        activeFenceToken: json['activeFenceToken'] as int,
        inputDigest: json['inputDigest'] as String,
        authorizedChunkIds: (json['authorizedChunkIds'] as List<dynamic>)
            .map((item) => item as String)
            .toSet(),
        modelVersionId: json['modelVersionId'] as String,
        runtimeVersion: json['runtimeVersion'] as String,
        promptTemplateVersion: json['promptTemplateVersion'] as String,
        executionPlanVersion: json['executionPlanVersion'] as String,
        producerFenceToken: json['producerFenceToken'] as int,
        producerAssignmentId: json['producerAssignmentId'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'grantId': grantId,
        'assignmentId': assignmentId,
        'activeFenceToken': activeFenceToken,
        'inputDigest': inputDigest,
        'authorizedChunkIds': authorizedChunkIds.toList(),
        'modelVersionId': modelVersionId,
        'runtimeVersion': runtimeVersion,
        'promptTemplateVersion': promptTemplateVersion,
        'executionPlanVersion': executionPlanVersion,
        'producerFenceToken': producerFenceToken,
        'producerAssignmentId': producerAssignmentId,
        'expiresAt': expiresAt.toIso8601String(),
      };
}

enum ResumeCompatibilityDecision {
  compatible,
  incompatibleModelSpace,
  incompatibleRuntime,
  incompatiblePromptTemplate,
  incompatibleExecutionPlan,
  inputDigestMismatch,
  grantExpired,
  unauthorizedChunk,
}

class ResumeCompatibilityResult {
  const ResumeCompatibilityResult({
    required this.decision,
    required this.permitted,
  });

  final ResumeCompatibilityDecision decision;
  final bool permitted;
}

abstract final class ResumeGrantValidator {
  static ResumeCompatibilityResult evaluate({
    required ResumeGrant grant,
    required String assignmentId,
    required int activeFenceToken,
    required String inputDigest,
    required String modelVersionId,
    required String runtimeVersion,
    required String promptTemplateVersion,
    required String executionPlanVersion,
    required Iterable<String> requestedChunkIds,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now().toUtc();
    if (grant.isExpired || grant.expiresAt.isBefore(current)) {
      return const ResumeCompatibilityResult(
        decision: ResumeCompatibilityDecision.grantExpired,
        permitted: false,
      );
    }
    if (grant.assignmentId != assignmentId || grant.activeFenceToken != activeFenceToken) {
      return const ResumeCompatibilityResult(
        decision: ResumeCompatibilityDecision.grantExpired,
        permitted: false,
      );
    }
    if (grant.inputDigest != inputDigest) {
      return const ResumeCompatibilityResult(
        decision: ResumeCompatibilityDecision.inputDigestMismatch,
        permitted: false,
      );
    }
    if (grant.modelVersionId != modelVersionId) {
      return const ResumeCompatibilityResult(
        decision: ResumeCompatibilityDecision.incompatibleModelSpace,
        permitted: false,
      );
    }
    if (grant.runtimeVersion != runtimeVersion) {
      return const ResumeCompatibilityResult(
        decision: ResumeCompatibilityDecision.incompatibleRuntime,
        permitted: false,
      );
    }
    if (grant.promptTemplateVersion != promptTemplateVersion) {
      return const ResumeCompatibilityResult(
        decision: ResumeCompatibilityDecision.incompatiblePromptTemplate,
        permitted: false,
      );
    }
    if (grant.executionPlanVersion != executionPlanVersion) {
      return const ResumeCompatibilityResult(
        decision: ResumeCompatibilityDecision.incompatibleExecutionPlan,
        permitted: false,
      );
    }
    for (final chunkId in requestedChunkIds) {
      if (!grant.authorizedChunkIds.contains(chunkId)) {
        return const ResumeCompatibilityResult(
          decision: ResumeCompatibilityDecision.unauthorizedChunk,
          permitted: false,
        );
      }
    }
    return const ResumeCompatibilityResult(
      decision: ResumeCompatibilityDecision.compatible,
      permitted: true,
    );
  }
}

class ResumeGrantRejectedException implements Exception {
  ResumeGrantRejectedException(this.result);

  final ResumeCompatibilityResult result;

  @override
  String toString() =>
      'ResumeGrantRejectedException(decision=${result.decision.name})';
}
