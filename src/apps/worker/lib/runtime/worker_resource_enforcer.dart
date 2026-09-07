import 'contribution_enforcement.dart';
import 'worker_resource_budget.dart';

enum ContributionModeId { balanced, performance }

enum ResourceBudgetViolation {
  cpuBudgetExceeded,
  memoryBudgetExceeded,
  storageBudgetExceeded,
}

class ResourceEnforcementVerdict {
  const ResourceEnforcementVerdict.allow()
      : allowed = true,
        violation = null,
        detail = null;

  const ResourceEnforcementVerdict.violation(this.violation, [this.detail]) : allowed = false;

  final bool allowed;
  final ResourceBudgetViolation? violation;
  final String? detail;

  String get telemetryCode => switch (violation) {
        ResourceBudgetViolation.cpuBudgetExceeded => 'CPU_BUDGET_EXCEEDED',
        ResourceBudgetViolation.memoryBudgetExceeded => 'MEMORY_BUDGET_EXCEEDED',
        ResourceBudgetViolation.storageBudgetExceeded => 'STORAGE_BUDGET_EXCEEDED',
        null => 'RESOURCE_BUDGET_OK',
      };
}

/// Local consent and per-class budget enforcement (Architecture Section 18).
///
/// Reports telemetry on violation; never retries or reassigns locally.
class WorkerResourceEnforcer {
  WorkerResourceEnforcer({
    required DeviceResourceCapacity capacity,
    ContributionModeId contributionModeId = ContributionModeId.balanced,
    int safetyReservePercent = 15,
    CpuEnforcementProfile cpuEnforcementProfile = CpuEnforcementProfile.productionV1,
  })  : _capacity = capacity,
        _contributionModeId = contributionModeId,
        _safetyReservePercent = safetyReservePercent,
        _cpuEnforcementProfile = cpuEnforcementProfile,
        effectiveBudgets = computeEffectiveResourceBudgets(
          capacity: capacity,
          contributionMultiplierBps: _multiplierForMode(contributionModeId),
          safetyReservePercent: safetyReservePercent,
        );

  final DeviceResourceCapacity _capacity;
  final ContributionModeId _contributionModeId;
  final int _safetyReservePercent;
  final CpuEnforcementProfile _cpuEnforcementProfile;
  final EffectiveResourceBudgets effectiveBudgets;

  int get approvedPercent => switch (_contributionModeId) {
        ContributionModeId.balanced => 30,
        ContributionModeId.performance => 50,
      };

  ResourceEnforcementVerdict evaluateRequest({
    required ResourceClassTotals reserved,
    required ResourceClassTotals requested,
  }) {
    final projected = reserved + requested;
    if (projected.cpuUnits > effectiveBudgets.cpuUnits) {
      return ResourceEnforcementVerdict.violation(
        ResourceBudgetViolation.cpuBudgetExceeded,
        'cpu ${projected.cpuUnits} > ${effectiveBudgets.cpuUnits}',
      );
    }
    if (projected.memoryBytes > effectiveBudgets.memoryBytes) {
      return ResourceEnforcementVerdict.violation(
        ResourceBudgetViolation.memoryBudgetExceeded,
        'memory ${projected.memoryBytes} > ${effectiveBudgets.memoryBytes}',
      );
    }
    if (projected.storageBytes > effectiveBudgets.storageBytes) {
      return ResourceEnforcementVerdict.violation(
        ResourceBudgetViolation.storageBudgetExceeded,
        'storage ${projected.storageBytes} > ${effectiveBudgets.storageBytes}',
      );
    }
    return const ResourceEnforcementVerdict.allow();
  }

  void ensureWithinBudgetOrThrow({
    required ResourceClassTotals reserved,
    required ResourceClassTotals requested,
  }) {
    final verdict = evaluateRequest(reserved: reserved, requested: requested);
    if (!verdict.allowed) {
      throw WorkerResourceEnforcementException(verdict);
    }
  }

  Map<String, dynamic> telemetryPayload(ResourceEnforcementVerdict verdict) {
    final approvedCeilingBps = approvedCpuCeilingBps(
      approvedPercent: approvedPercent,
      deviceCpuUnits: _capacity.cpuUnits,
    );
    return {
      'code': verdict.telemetryCode,
      'approvedPercent': approvedPercent,
      'contributionModeId': _contributionModeId.name,
      'cpuEnforcement': {
        'measurementWindowMs': _cpuEnforcementProfile.measurementWindowMs,
        'coveredProcessScope': _cpuEnforcementProfile.coveredProcessScope,
        'toleratedBurstBps': _cpuEnforcementProfile.toleratedBurstBps,
        'controlStopReactionBoundMs': _cpuEnforcementProfile.controlStopReactionBoundMs,
        'enforcementMechanism': _cpuEnforcementProfile.enforcementMechanism,
        'approvedCeilingBps': approvedCeilingBps,
      },
      'effectiveBudgets': {
        'cpuUnits': effectiveBudgets.cpuUnits,
        'memoryBytes': effectiveBudgets.memoryBytes,
        'storageBytes': effectiveBudgets.storageBytes,
      },
      if (verdict.detail != null) 'detail': verdict.detail,
      'safetyReservePercent': _safetyReservePercent,
      'capacity': {
        'cpuUnits': _capacity.cpuUnits,
        'totalRamBytes': _capacity.totalRamBytes,
        'availableRamBytes': _capacity.availableRamBytes,
      },
    };
  }

  WorkerResourceEnforcer reconfigured({
    ContributionModeId? contributionModeId,
    int? safetyReservePercent,
    CpuEnforcementProfile? cpuEnforcementProfile,
  }) {
    return WorkerResourceEnforcer(
      capacity: _capacity,
      contributionModeId: contributionModeId ?? _contributionModeId,
      safetyReservePercent: safetyReservePercent ?? _safetyReservePercent,
      cpuEnforcementProfile: cpuEnforcementProfile ?? _cpuEnforcementProfile,
    );
  }

  static int _multiplierForMode(ContributionModeId modeId) {
    return switch (modeId) {
      ContributionModeId.balanced => contributionBudgetMultiplierBps(30),
      ContributionModeId.performance => contributionBudgetMultiplierBps(50),
    };
  }
}

class WorkerResourceEnforcementException implements Exception {
  WorkerResourceEnforcementException(this.verdict);

  final ResourceEnforcementVerdict verdict;

  @override
  String toString() => 'WorkerResourceEnforcementException(${verdict.telemetryCode})';
}
