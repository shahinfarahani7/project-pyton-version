/// Integer budget math aligned with backend `resource_budget.py`.
class ResourceClassTotals {
  const ResourceClassTotals({
    required this.cpuUnits,
    required this.memoryBytes,
    required this.storageBytes,
  });

  final int cpuUnits;
  final int memoryBytes;
  final int storageBytes;

  ResourceClassTotals operator +(ResourceClassTotals other) {
    return ResourceClassTotals(
      cpuUnits: cpuUnits + other.cpuUnits,
      memoryBytes: memoryBytes + other.memoryBytes,
      storageBytes: storageBytes + other.storageBytes,
    );
  }
}

class EffectiveResourceBudgets {
  const EffectiveResourceBudgets({
    required this.cpuUnits,
    required this.memoryBytes,
    required this.storageBytes,
  });

  final int cpuUnits;
  final int memoryBytes;
  final int storageBytes;
}

class DeviceResourceCapacity {
  const DeviceResourceCapacity({
    required this.cpuUnits,
    required this.totalRamBytes,
    required this.availableRamBytes,
    required this.safetyReserveBytes,
    required this.storageAvailableBytes,
    required this.storageMinimumFreeBytes,
    required this.maxAiStorageBytes,
  });

  final int cpuUnits;
  final int totalRamBytes;
  final int availableRamBytes;
  final int safetyReserveBytes;
  final int storageAvailableBytes;
  final int storageMinimumFreeBytes;
  final int maxAiStorageBytes;
}

int contributionBudgetMultiplierBps(int approvedPercent) {
  if (approvedPercent < 1 || approvedPercent > 100) {
    throw ArgumentError.value(approvedPercent, 'approvedPercent', 'out of range');
  }
  return approvedPercent * 100;
}

int applyContributionBudget({
  required int capacityUnits,
  required int budgetMultiplierBps,
}) {
  if (capacityUnits < 0) {
    throw ArgumentError.value(capacityUnits, 'capacityUnits');
  }
  if (budgetMultiplierBps < 0 || budgetMultiplierBps > 10000) {
    throw ArgumentError.value(budgetMultiplierBps, 'budgetMultiplierBps');
  }
  return (capacityUnits * budgetMultiplierBps) ~/ 10000;
}

EffectiveResourceBudgets computeEffectiveResourceBudgets({
  required DeviceResourceCapacity capacity,
  required int contributionMultiplierBps,
  int safetyReservePercent = 15,
}) {
  final userCpuBudget = applyContributionBudget(
    capacityUnits: capacity.cpuUnits,
    budgetMultiplierBps: contributionMultiplierBps,
  );
  final userMemoryLimit = applyContributionBudget(
    capacityUnits: capacity.totalRamBytes,
    budgetMultiplierBps: contributionMultiplierBps,
  );
  final memorySafety = [
    capacity.safetyReserveBytes,
    (capacity.totalRamBytes * safetyReservePercent) ~/ 100,
  ].reduce((left, right) => left > right ? left : right);
  final availableMemoryBudget = (capacity.availableRamBytes - memorySafety).clamp(0, 1 << 62);
  final effectiveMemory = userMemoryLimit < availableMemoryBudget ? userMemoryLimit : availableMemoryBudget;
  final storageFreeBudget = (capacity.storageAvailableBytes - capacity.storageMinimumFreeBytes)
      .clamp(0, 1 << 62);
  final effectiveStorage =
      capacity.maxAiStorageBytes < storageFreeBudget ? capacity.maxAiStorageBytes : storageFreeBudget;

  return EffectiveResourceBudgets(
    cpuUnits: userCpuBudget,
    memoryBytes: effectiveMemory,
    storageBytes: effectiveStorage,
  );
}
