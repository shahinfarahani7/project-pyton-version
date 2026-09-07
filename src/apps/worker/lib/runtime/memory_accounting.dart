import '../telemetry/resource_envelope_catalog.dart';

enum MemoryCommitmentKind { base, resident, taskPeak, transfer }

enum MemoryAttributionStatus { known, uncertain }

class MemoryCommitment {
  const MemoryCommitment({
    required this.kind,
    required this.commitmentKey,
    required this.memoryBytes,
    required this.peakMemoryBytes,
    this.residentIdentity,
  });

  final MemoryCommitmentKind kind;
  final String commitmentKey;
  final int memoryBytes;
  final int peakMemoryBytes;
  final String? residentIdentity;
}

class MemoryAccountingSnapshot {
  MemoryAccountingSnapshot({
    required this.accountedBytes,
    required this.remainingBytes,
    required this.attributionStatus,
    required this.commitments,
  });

  final int accountedBytes;
  final int remainingBytes;
  final MemoryAttributionStatus attributionStatus;
  final List<MemoryCommitment> commitments;

  Map<String, dynamic> toJson() => {
        'accountedBytes': accountedBytes,
        'remainingBytes': remainingBytes,
        'attributionStatus': attributionStatus.name,
        'commitments': commitments
            .map(
              (entry) => {
                'kind': entry.kind.name,
                'commitmentKey': entry.commitmentKey,
                'memoryBytes': entry.memoryBytes,
                'peakMemoryBytes': entry.peakMemoryBytes,
                if (entry.residentIdentity != null) 'residentIdentity': entry.residentIdentity,
              },
            )
            .toList(),
      };
}

/// Local memory accounting basis: base/resident/task_peak/transfer (v2 §16, A04).
abstract final class MemoryAccounting {
  static const fixedRuntimeBaseBytes = 256 * 1024 * 1024;
  static const defaultResidentModelBytes = 768 * 1024 * 1024;

  static MemoryCommitment baseRuntimeCommitment() => MemoryCommitment(
        kind: MemoryCommitmentKind.base,
        commitmentKey: 'runtime_base',
        memoryBytes: fixedRuntimeBaseBytes,
        peakMemoryBytes: fixedRuntimeBaseBytes,
      );

  static MemoryCommitment residentCommitment(String modelVersionId, {int? memoryBytes}) =>
      MemoryCommitment(
        kind: MemoryCommitmentKind.resident,
        commitmentKey: 'resident:$modelVersionId',
        memoryBytes: memoryBytes ?? defaultResidentModelBytes,
        peakMemoryBytes: memoryBytes ?? defaultResidentModelBytes,
        residentIdentity: modelVersionId,
      );

  static MemoryCommitment taskPeakCommitment({
    required String assignmentId,
    required String taskType,
  }) {
    final envelope = ResourceEnvelopeCatalog.forTaskType(taskType);
    final peak = envelope.peakMemoryBytes;
    return MemoryCommitment(
      kind: MemoryCommitmentKind.taskPeak,
      commitmentKey: 'task_peak:$assignmentId',
      memoryBytes: peak,
      peakMemoryBytes: peak,
    );
  }

  static List<MemoryCommitment> dedupeResidents(List<MemoryCommitment> commitments) {
    final seen = <String>{};
    final result = <MemoryCommitment>[];
    for (final commitment in commitments) {
      if (commitment.kind != MemoryCommitmentKind.resident) {
        result.add(commitment);
        continue;
      }
      final identity = commitment.residentIdentity ?? commitment.commitmentKey;
      if (seen.contains(identity)) {
        continue;
      }
      seen.add(identity);
      result.add(commitment);
    }
    return result;
  }

  static int accountedBytes(List<MemoryCommitment> commitments) {
    var total = 0;
    for (final commitment in dedupeResidents(commitments)) {
      total += commitment.peakMemoryBytes > commitment.memoryBytes
          ? commitment.peakMemoryBytes
          : commitment.memoryBytes;
    }
    return total;
  }

  static MemoryAccountingSnapshot evaluate({
    required int effectiveMemoryLimitBytes,
    required List<MemoryCommitment> commitments,
    MemoryCommitment? requested,
    MemoryAttributionStatus attributionStatus = MemoryAttributionStatus.known,
  }) {
    final active = [...commitments, if (requested != null) requested];
    if (attributionStatus == MemoryAttributionStatus.uncertain) {
      return MemoryAccountingSnapshot(
        accountedBytes: accountedBytes(active),
        remainingBytes: 0,
        attributionStatus: attributionStatus,
        commitments: active,
      );
    }
    final accounted = accountedBytes(active);
    final remaining = (effectiveMemoryLimitBytes - accounted).clamp(0, 1 << 62);
    return MemoryAccountingSnapshot(
      accountedBytes: accounted,
      remainingBytes: remaining,
      attributionStatus: attributionStatus,
      commitments: active,
    );
  }
}
