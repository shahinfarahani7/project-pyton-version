import 'dart:io';

import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/platform/worker_runtime_channel.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/worker_app_update.dart';
import 'package:edgemint_worker/ui/worker_offline_dialog.dart';
import 'package:edgemint_worker/worker_app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  testWidgets('offline dialog blocks every action and closes when online', (
    tester,
  ) async {
    var offline = false;
    var taps = 0;
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return WorkerOfflineGate(
              offline: offline,
              child: Scaffold(
                body: TextButton(
                  onPressed: () => taps += 1,
                  child: const Text('Do something'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No connection'), findsNothing);
    await tester.tap(find.text('Do something'));
    await tester.pump();
    expect(taps, 1);

    rebuild(() => offline = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No connection'), findsOneWidget);
    expect(
      find.textContaining('Connect to Wi-Fi or mobile data'),
      findsOneWidget,
    );
    expect(tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse);

    await tester.tap(find.text('Do something'), warnIfMissed: false);
    await tester.pump();
    expect(taps, 1);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pump();
    expect(find.text('No connection'), findsOneWidget);
    expect(find.text('Do something'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(find.text('No connection'), findsOneWidget);

    rebuild(() => offline = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No connection'), findsNothing);
    await tester.tap(find.text('Do something'));
    await tester.pump();
    expect(taps, 2);

    rebuild(() => offline = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No connection'), findsOneWidget);
  });

  testWidgets('removing the offline gate does not throw', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WorkerOfflineGate(
          offline: true,
          child: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('No connection'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test(
    'device network watch blocks worker actions until the radio returns',
    () async {
      final channel = _NetworkChannel(NetworkKind.offline);
      final requests = _OfflineHttpClient();
      final controller = WorkerAppController(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
        platform: channel,
        httpClient: requests,
        encryptedStore: InMemoryEncryptedStore(),
      );
      addTearDown(controller.dispose);

      controller.backendOnline = true;
      controller.workerEnrolled = true;
      controller.modelPhase = ModelInstallPhase.ready;
      expect(controller.isDeviceOffline, isFalse);
      expect(controller.canAcceptAssignments, isTrue);

      var notices = 0;
      controller.addListener(() => notices += 1);

      await controller.refreshDeviceNetwork();
      expect(controller.isDeviceOffline, isTrue);
      expect(controller.canAcceptAssignments, isFalse);
      expect(notices, 1);

      await controller.refreshDeviceNetwork();
      expect(notices, 1);

      await controller.refreshBackendHealth();
      expect(requests.sent, 0);
      expect(controller.backendOnline, isTrue);
      final noticesAfterHealth = notices;

      controller.setAvailable(false);
      expect(controller.available, isTrue);
      await controller.downloadGemmaModel();
      expect(controller.modelPhase, ModelInstallPhase.ready);
      controller.appUpdatePhase = WorkerAppUpdatePhase.available;
      controller.appUpdateVersionName = '1.2.3';
      await controller.installOfferedAppUpdate();
      expect(controller.appUpdatePhase, WorkerAppUpdatePhase.available);
      expect(controller.appUpdateError, isNull);
      expect(
        await controller.signInWithEmailPassword(
          email: 'dev-user@edgemint.local',
          password: 'secret-pass',
        ),
        'Connect to the internet to continue.',
      );
      expect(requests.sent, 0);

      channel.network = NetworkKind.wifi;
      await controller.refreshDeviceNetwork();
      expect(controller.isDeviceOffline, isFalse);
      expect(controller.canAcceptAssignments, isTrue);
      expect(notices, noticesAfterHealth + 1);
    },
  );
}

class _OfflineHttpClient extends http.BaseClient {
  int sent = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sent += 1;
    throw const SocketException('offline');
  }
}

class _NetworkChannel extends NoopWorkerRuntimeChannel {
  _NetworkChannel(this.network);

  NetworkKind network;

  @override
  Future<DeviceSnapshot> readDeviceSnapshot() async {
    return snapshot.copyWith(network: network);
  }
}
