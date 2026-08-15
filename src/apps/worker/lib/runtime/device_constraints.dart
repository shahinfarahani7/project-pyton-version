import 'execution_policy.dart';
import 'device_snapshot.dart';
import 'runtime_exceptions.dart';

enum ConstraintViolation {
  unavailable,
  missingConsent,
  batteryLow,
  storageLow,
  thermalCritical,
  networkOffline,
  scheduleBlocked,
}

class ConstraintDecision {
  const ConstraintDecision.pass()
      : allowed = true,
        violation = null,
        detail = null;

  const ConstraintDecision.block(this.violation, [this.detail])
      : allowed = false;

  final bool allowed;
  final ConstraintViolation? violation;
  final String? detail;
}

class DeviceConstraints {
  const DeviceConstraints({
    this.requireChargingForHeavyTasks = false,
    this.allowCellular = true,
  });

  final bool requireChargingForHeavyTasks;
  final bool allowCellular;

  ConstraintDecision evaluate(DeviceSnapshot snapshot, {bool heavyTask = false}) {
    if (!snapshot.available) {
      return const ConstraintDecision.block(ConstraintViolation.unavailable, 'Worker availability is off');
    }
    for (final consent in ExecutionPolicy.requiredConsents) {
      if (!snapshot.consentsGranted.contains(consent)) {
        return ConstraintDecision.block(ConstraintViolation.missingConsent, 'Missing consent: $consent');
      }
    }
    if (!snapshot.isEmulator &&
        snapshot.batteryPercent < ExecutionPolicy.minimumBatteryPercent) {
      return const ConstraintDecision.block(ConstraintViolation.batteryLow);
    }
    if (snapshot.freeStorageMb < ExecutionPolicy.minimumStorageMb) {
      return const ConstraintDecision.block(ConstraintViolation.storageLow);
    }
    if (snapshot.thermalState == ThermalState.critical) {
      return const ConstraintDecision.block(ConstraintViolation.thermalCritical);
    }
    if (snapshot.network == NetworkKind.offline) {
      return const ConstraintDecision.block(ConstraintViolation.networkOffline);
    }
    if (!allowCellular && snapshot.network == NetworkKind.cellular) {
      return const ConstraintDecision.block(ConstraintViolation.networkOffline, 'Cellular blocked by preference');
    }
    if (!snapshot.withinSchedule) {
      return const ConstraintDecision.block(ConstraintViolation.scheduleBlocked);
    }
    if (heavyTask && requireChargingForHeavyTasks && !snapshot.isCharging && !snapshot.isEmulator) {
      return const ConstraintDecision.block(ConstraintViolation.batteryLow, 'Charging required for heavy tasks');
    }
    return const ConstraintDecision.pass();
  }

  void ensureOrThrow(DeviceSnapshot snapshot, {bool heavyTask = false}) {
    final decision = evaluate(snapshot, heavyTask: heavyTask);
    if (!decision.allowed) {
      throw ConstraintBlockedException(decision.violation!, decision.detail);
    }
  }
}
