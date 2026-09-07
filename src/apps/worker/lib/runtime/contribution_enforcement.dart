/// Windowed CPU contribution enforcement profile (Architecture v2 §16.1).
class CpuEnforcementProfile {
  const CpuEnforcementProfile({
    required this.measurementWindowMs,
    required this.coveredProcessScope,
    required this.toleratedBurstBps,
    required this.controlStopReactionBoundMs,
    required this.enforcementMechanism,
  });

  final int measurementWindowMs;
  final String coveredProcessScope;
  final int toleratedBurstBps;
  final int controlStopReactionBoundMs;
  final String enforcementMechanism;

  static const productionV1 = CpuEnforcementProfile(
    measurementWindowMs: 5000,
    coveredProcessScope: 'aggregate_worker_process_native',
    toleratedBurstBps: 1200,
    controlStopReactionBoundMs: 3000,
    enforcementMechanism: 'windowed_cpu_share_v1',
  );
}

int cpuUsageBpsFromUnits(int cpuUnits) {
  if (cpuUnits < 0) {
    throw ArgumentError.value(cpuUnits, 'cpuUnits', 'must be non-negative');
  }
  final bps = cpuUnits * 100;
  return bps > 10000 ? 10000 : bps;
}

int approvedCpuCeilingBps({
  required int approvedPercent,
  required int deviceCpuUnits,
}) {
  final effectiveUnits = (deviceCpuUnits * approvedPercent) ~/ 100;
  return cpuUsageBpsFromUnits(effectiveUnits);
}

int burstCeilingBps({
  required int approvedCeilingBps,
  required int toleratedBurstBps,
}) {
  final burst = approvedCeilingBps + toleratedBurstBps;
  return burst > 10000 ? 10000 : burst;
}

bool isWindowedCpuSampleWithinBound({
  required int observedCpuUsageBps,
  required int approvedCeilingBps,
  required CpuEnforcementProfile profile,
}) {
  if (observedCpuUsageBps < 0 || observedCpuUsageBps > 10000) {
    return false;
  }
  return observedCpuUsageBps <=
      burstCeilingBps(
        approvedCeilingBps: approvedCeilingBps,
        toleratedBurstBps: profile.toleratedBurstBps,
      );
}
