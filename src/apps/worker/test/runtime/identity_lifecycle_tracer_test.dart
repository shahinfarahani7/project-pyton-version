import 'package:flutter_test/flutter_test.dart';

import 'package:edgemint_worker/runtime/identity_lifecycle_tracer.dart';

void main() {
  group('IdentityLifecycleTracer', () {
    setUp(IdentityLifecycleTracer.instance.resetForTests);

    test('records native handle counters and recent mutations', () {
      final tracer = IdentityLifecycleTracer.instance;
      tracer.recordNativeModelCreate(caller: 'test');
      tracer.recordNativeSessionOpen(caller: 'test', stageId: 'inference');
      tracer.recordNativeSessionClose(caller: 'test', stageId: 'inference');
      tracer.recordIdentityClear(caller: 'test', reason: 'missing_file');

      final view = tracer.heartbeatView(
        runtimeGeneration: 2,
        nativeHandlesInvalidated: false,
        hasActiveAssignment: false,
      );

      expect(view['nativeHandleCounters'], {
        'modelCreate': 1,
        'modelClose': 0,
        'sessionCreate': 1,
        'sessionClose': 1,
        'identityClear': 1,
      });
      expect(view['recentMutations'], isNotEmpty);
    });

    test('guardBootstrap serializes overlapping bootstrap depth', () async {
      final tracer = IdentityLifecycleTracer.instance;
      expect(tracer.bootstrapInFlight, isFalse);

      await tracer.guardBootstrap(
        caller: 'test',
        body: () async {
          expect(tracer.bootstrapInFlight, isTrue);
        },
      );

      expect(tracer.bootstrapInFlight, isFalse);
    });

    test('detects idle churn when clears happen without assignment', () {
      final tracer = IdentityLifecycleTracer.instance;
      tracer.recordIdentityClear(caller: 'test', reason: 'one');
      tracer.recordIdentityClear(caller: 'test', reason: 'two');

      expect(
        tracer.detectIdleChurn(hasActiveAssignment: false),
        isTrue,
      );
      expect(
        tracer.detectIdleChurn(hasActiveAssignment: true),
        isFalse,
      );
    });
  });
}
