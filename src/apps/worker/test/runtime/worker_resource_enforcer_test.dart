import 'package:edgemint_worker/runtime/worker_resource_budget.dart';
import 'package:edgemint_worker/runtime/worker_resource_enforcer.dart';
import 'package:flutter_test/flutter_test.dart';

const _capacity = DeviceResourceCapacity(
  cpuUnits: 100,
  totalRamBytes: 12_884_901_888,
  availableRamBytes: 8_589_934_592,
  safetyReserveBytes: 536_870_912,
  storageAvailableBytes: 21_474_836_480,
  storageMinimumFreeBytes: 1_073_741_824,
  maxAiStorageBytes: 5_368_709_120,
);

void main() {
  test('30% balanced mode maps to 3000 bps multiplier', () {
    expect(contributionBudgetMultiplierBps(30), 3000);
    expect(
      WorkerResourceEnforcer(
        capacity: _capacity,
        contributionModeId: ContributionModeId.balanced,
      ).approvedPercent,
      30,
    );
  });

  test('50% performance mode maps to 5000 bps multiplier', () {
    expect(contributionBudgetMultiplierBps(50), 5000);
    expect(
      WorkerResourceEnforcer(
        capacity: _capacity,
        contributionModeId: ContributionModeId.performance,
      ).approvedPercent,
      50,
    );
  });

  test('balanced budgets are lower than performance budgets', () {
    final balanced = WorkerResourceEnforcer(
      capacity: _capacity,
      contributionModeId: ContributionModeId.balanced,
    ).effectiveBudgets;
    final performance = WorkerResourceEnforcer(
      capacity: _capacity,
      contributionModeId: ContributionModeId.performance,
    ).effectiveBudgets;

    expect(balanced.cpuUnits, 30);
    expect(performance.cpuUnits, 50);
    expect(balanced.memoryBytes, lessThan(performance.memoryBytes));
  });

  test('memory request above budget returns violation telemetry', () {
    final enforcer = WorkerResourceEnforcer(
      capacity: _capacity,
      contributionModeId: ContributionModeId.balanced,
    );
    final verdict = enforcer.evaluateRequest(
      reserved: const ResourceClassTotals(cpuUnits: 0, memoryBytes: 0, storageBytes: 0),
      requested: ResourceClassTotals(
        cpuUnits: 1,
        memoryBytes: enforcer.effectiveBudgets.memoryBytes + 1,
        storageBytes: 1,
      ),
    );

    expect(verdict.allowed, isFalse);
    expect(verdict.telemetryCode, 'MEMORY_BUDGET_EXCEEDED');
    expect(enforcer.telemetryPayload(verdict)['approvedPercent'], 30);
  });

  test('ensureWithinBudgetOrThrow raises without scheduling side effects', () {
    final enforcer = WorkerResourceEnforcer(
      capacity: _capacity,
      contributionModeId: ContributionModeId.performance,
    );
    expect(
      () => enforcer.ensureWithinBudgetOrThrow(
        reserved: const ResourceClassTotals(cpuUnits: 0, memoryBytes: 0, storageBytes: 0),
        requested: ResourceClassTotals(
          cpuUnits: enforcer.effectiveBudgets.cpuUnits + 1,
          memoryBytes: 0,
          storageBytes: 0,
        ),
      ),
      throwsA(isA<WorkerResourceEnforcementException>()),
    );
  });

  test('reconfigured enforcer applies new contribution mode budgets', () {
    final enforcer = WorkerResourceEnforcer(
      capacity: _capacity,
      contributionModeId: ContributionModeId.balanced,
    );
    final upgraded = enforcer.reconfigured(contributionModeId: ContributionModeId.performance);
    expect(upgraded.approvedPercent, 50);
    expect(upgraded.effectiveBudgets.cpuUnits, 50);
  });
}
