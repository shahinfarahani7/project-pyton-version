import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edgemint_worker/runtime/process_lifecycle_coordinator.dart';

void main() {
  group('ProcessLifecycleCoordinator', () {
    test('process termination invalidates native handles and bumps generation', () async {
      var invalidated = false;
      final coordinator = ProcessLifecycleCoordinator(
        onInvalidateNativeHandles: (_) async {
          invalidated = true;
        },
      );

      expect(coordinator.runtimeGeneration, 1);
      expect(coordinator.requiresFreshGrantReconciliation, isFalse);

      await coordinator.markProcessTerminated(reason: 'process_death');

      expect(invalidated, isTrue);
      expect(coordinator.runtimeGeneration, 2);
      expect(coordinator.nativeHandlesInvalidated, isTrue);
      expect(coordinator.requiresFreshGrantReconciliation, isTrue);
      expect(coordinator.phase, ProcessLifecyclePhase.processTerminated);
    });

    test('fresh grant reconciliation clears invalidation after server authorization', () async {
      final coordinator = ProcessLifecycleCoordinator();
      await coordinator.markProcessTerminated(reason: 'device_reboot');

      coordinator.acknowledgeFreshGrantReconciliation();

      expect(coordinator.requiresFreshGrantReconciliation, isFalse);
      expect(coordinator.nativeHandlesInvalidated, isFalse);
      expect(coordinator.phase, ProcessLifecyclePhase.foreground);
    });

    test('app lifecycle detached marks process terminated', () {
      final coordinator = ProcessLifecycleCoordinator();
      coordinator.handleAppLifecycleState(AppLifecycleState.detached);

      expect(coordinator.phase, ProcessLifecyclePhase.processTerminated);
      expect(coordinator.requiresFreshGrantReconciliation, isTrue);
      expect(coordinator.runtimeGeneration, 2);
    });

    test('reboot pending keeps reconciliation required until fresh grant', () {
      final coordinator = ProcessLifecycleCoordinator();
      coordinator.markRebootPending();

      expect(coordinator.phase, ProcessLifecyclePhase.rebootPending);
      expect(coordinator.requiresFreshGrantReconciliation, isTrue);
    });
  });
}
