import 'device_capability_report.dart';
import 'device_snapshot.dart';
import '../telemetry/resource_envelope_catalog.dart';
import 'memory_accounting.dart';
import 'runtime_exclusive_group_enforcer.dart';
import 'worker_resource_budget.dart';

class WorkerCalibrationView {
  const WorkerCalibrationView({
    required this.profileVersion,
    required this.suiteVersion,
    this.measuredAt,
  });

  final int profileVersion;
  final String suiteVersion;
  final DateTime? measuredAt;

  Map<String, dynamic> toJson() {
    return {
      'profileVersion': profileVersion,
      'suiteVersion': suiteVersion,
      if (measuredAt != null) 'measuredAt': measuredAt!.toUtc().toIso8601String(),
    };
  }
}

class WorkerResourceReservationEntry {
  const WorkerResourceReservationEntry({
    required this.assignmentId,
    required this.runtimeClass,
    required this.cpuUnits,
    required this.memoryBytes,
    required this.storageBytes,
  });

  final String assignmentId;
  final String runtimeClass;
  final int cpuUnits;
  final int memoryBytes;
  final int storageBytes;

  Map<String, dynamic> toJson() {
    return {
      'assignmentId': assignmentId,
      'runtimeClass': runtimeClass,
      'cpuUnits': cpuUnits,
      'memoryBytes': memoryBytes,
      'storageBytes': storageBytes,
    };
  }
}

class WorkerResourceReservationsView {
  const WorkerResourceReservationsView({
    required this.active,
    required this.totals,
  });

  final List<WorkerResourceReservationEntry> active;
  final ResourceClassTotals totals;

  Map<String, dynamic> toJson() {
    return {
      'active': active.map((entry) => entry.toJson()).toList(),
      'totals': {
        'cpuUnits': totals.cpuUnits,
        'memoryBytes': totals.memoryBytes,
        'storageBytes': totals.storageBytes,
      },
    };
  }
}

/// Inputs for Section 39 heartbeat telemetry (capability, consent, calibration, reservations).
class WorkerHeartbeatTelemetryContext {
  const WorkerHeartbeatTelemetryContext({
    required this.sequence,
    required this.snapshot,
    this.currentLeases = const [],
    this.installedModels = const [],
    this.loadedModelIds = const [],
    this.cpuUsageBps = 0,
    this.runtimeExclusiveGroups,
    this.runtimeSessionsOverride,
    this.calibrationView,
    this.activeReservation,
    this.contributionModeId = 'balanced',
    this.includeCapabilitySnapshot = true,
    this.identityLifecycleView,
  });

  final int sequence;
  final DeviceSnapshot snapshot;
  final List<String> currentLeases;
  final List<Map<String, String>> installedModels;
  final List<String> loadedModelIds;
  final int cpuUsageBps;
  final RuntimeExclusiveGroupEnforcer? runtimeExclusiveGroups;
  final Map<String, int>? runtimeSessionsOverride;
  final WorkerCalibrationView? calibrationView;
  final WorkerResourceReservationEntry? activeReservation;
  final String contributionModeId;
  final bool includeCapabilitySnapshot;
  final Map<String, dynamic>? identityLifecycleView;
}

/// Builds heartbeat payloads aligned with Section 39 and dsl/schemas/workerheartbeattelemetry.schema.json.
abstract final class WorkerHeartbeatTelemetry {
  static Map<String, dynamic> build(WorkerHeartbeatTelemetryContext context) {
    final capability = DeviceCapabilityReport.fromDispatcher(snapshot: context.snapshot);
    final runtimeSessions = context.runtimeSessionsOverride ??
        _runtimeSessions(context.runtimeExclusiveGroups);
    final reservationsView = _reservationsView(context.activeReservation);
    final memoryAccounting = _memoryAccountingView(
      context: context,
      reservationsView: reservationsView,
    );

    return {
      'sequence': context.sequence,
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      'batteryBps': context.snapshot.batteryPercent * 100,
      'charging': context.snapshot.isCharging,
      'thermalState': capability['thermal']['state'],
      'freeRamBytes': capability['memory']['availableBytes'],
      'freeStorageBytes': capability['storage']['availableBytes'],
      'network': capability['network']['type'],
      'currentLeases': context.currentLeases,
      'installedModels': context.installedModels,
      if (context.includeCapabilitySnapshot) 'capabilitySnapshot': capability,
      'cpuUsageBps': context.cpuUsageBps,
      'loadedModelIds': context.loadedModelIds,
      'runtimeSessions': runtimeSessions,
      'consentSnapshot': {
        'grantedConsents': context.snapshot.consentsGranted,
        'contributionModeId': context.contributionModeId,
      },
      if (context.calibrationView != null) 'calibrationView': context.calibrationView!.toJson(),
      if (reservationsView != null) 'resourceReservationsView': reservationsView,
      if (memoryAccounting != null) 'memoryAccounting': memoryAccounting,
      if (context.identityLifecycleView != null)
        'identityLifecycleView': context.identityLifecycleView,
    };
  }

  static Map<String, dynamic>? _memoryAccountingView({
    required WorkerHeartbeatTelemetryContext context,
    required Map<String, dynamic>? reservationsView,
  }) {
    final commitments = <MemoryCommitment>[MemoryAccounting.baseRuntimeCommitment()];
    for (final modelId in context.loadedModelIds) {
      commitments.add(MemoryAccounting.residentCommitment(modelId));
    }
    final active = context.activeReservation;
    if (active != null) {
      commitments.add(
        MemoryCommitment(
          kind: MemoryCommitmentKind.taskPeak,
          commitmentKey: 'task_peak:${active.assignmentId}',
          memoryBytes: active.memoryBytes,
          peakMemoryBytes: active.memoryBytes,
        ),
      );
    }
    final capability = DeviceCapabilityReport.fromDispatcher(snapshot: context.snapshot);
    final memory = capability['memory'] as Map<String, dynamic>;
    final available = memory['availableBytes'] as int? ?? 0;
    final total = memory['totalRamBytes'] as int? ?? available;
    final effectiveLimit = (total * 0.5).round();
    final snapshot = MemoryAccounting.evaluate(
      effectiveMemoryLimitBytes: effectiveLimit,
      commitments: commitments,
      attributionStatus:
          available > 0 ? MemoryAttributionStatus.known : MemoryAttributionStatus.uncertain,
    );
    return snapshot.toJson();
  }

  static Map<String, int> _runtimeSessions(RuntimeExclusiveGroupEnforcer? enforcer) {
    if (enforcer == null) {
      return const {};
    }
    return {
      'mediapipe_llm': enforcer.heavyLlmActive ? 1 : 0,
      'paddle_ocr': enforcer.activeOcrSessions,
    };
  }

  static Map<String, dynamic>? _reservationsView(WorkerResourceReservationEntry? active) {
    if (active == null) {
      return null;
    }
    final totals = ResourceClassTotals(
      cpuUnits: active.cpuUnits,
      memoryBytes: active.memoryBytes,
      storageBytes: active.storageBytes,
    );
    return WorkerResourceReservationsView(
      active: [active],
      totals: totals,
    ).toJson();
  }

  static WorkerResourceReservationEntry reservationForTask({
    required String assignmentId,
    required String taskType,
  }) {
    final envelope = ResourceEnvelopeCatalog.forTaskType(taskType);
    return WorkerResourceReservationEntry(
      assignmentId: assignmentId,
      runtimeClass: envelope.runtimeClass,
      cpuUnits: envelope.cpuUnits,
      memoryBytes: envelope.peakMemoryBytes,
      storageBytes: 0,
    );
  }
}
