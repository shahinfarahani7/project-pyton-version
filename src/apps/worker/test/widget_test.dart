import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/execution_status.dart';
import 'package:edgemint_worker/runtime/worker_app_update.dart';
import 'package:edgemint_worker/ui/tabs/worker_home_tab.dart';
import 'package:edgemint_worker/ui/worker_theme.dart';
import 'package:edgemint_worker/ui/worker_widgets.dart';
import 'package:edgemint_worker/worker_app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'home shows the character and earnings chart without boost prompt',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = WorkerAppController(
        config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
        encryptedStore: InMemoryEncryptedStore(),
      );
      controller.setAvailable(false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildWorkerTheme(),
          home: WorkerHomeTab(controller: controller),
        ),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel('Worker character waiting for a task'),
        findsOneWidget,
      );
      expect(find.text('Tasks completed'), findsOneWidget);
      expect(find.text('Fibonai'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('0 FIBON'), findsOneWidget);
      expect(find.text(r'$0.00'), findsNothing);
      controller.tasksProcessed = 2;
      controller.notifyListeners();
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1.5 FIBON'), findsOneWidget);
      expect(
        tester.widget<WorkerLineChart>(find.byType(WorkerLineChart)).values,
        const [0, 0, 0, 0, 0, 0, 0],
      );
      controller.fibonaiDailyPoints = const [0, 0, 0, 0, 40, 0, 40];
      controller.notifyListeners();
      await tester.pump();
      expect(
        tester.widget<WorkerLineChart>(find.byType(WorkerLineChart)).values,
        const [0, 0, 0, 0, 40, 0, 40],
      );
      expect(find.textContaining('80 Fibonai over the last 7 days'), findsOneWidget);
      expect(find.text('AI model'), findsNothing);
      expect(find.text('Download model'), findsNothing);
      expect(find.textContaining('Qwen'), findsNothing);
      expect(find.text('Earnings'), findsOneWidget);
      expect(find.textContaining('not guaranteed'), findsWidgets);
      expect(find.text('Boost your worker'), findsNothing);
      expect(find.text('Turn availability on'), findsNothing);
      expect(find.text('App update'), findsNothing);
      expect(find.text('Model update'), findsNothing);
      expect(find.text('Required app update'), findsNothing);
    },
  );

  testWidgets('home shows the running character while a task is active', (
    tester,
  ) async {
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    controller.setAvailable(false);
    controller.executionStatus = const ExecutionStatus(
      phase: ExecutionPhase.running,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: WorkerHomeTab(controller: controller),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel('Worker character running a task'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Worker character waiting for a task'),
      findsNothing,
    );
  });

  testWidgets('home shows download progress card while model is installing', (
    tester,
  ) async {
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    controller.setAvailable(false);
    controller.modelPhase = ModelInstallPhase.downloading;
    controller.modelProgress = 0.42;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: WorkerHomeTab(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Downloading 42%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    controller.modelProgress = 1;
    controller.notifyListeners();
    await tester.pump();

    expect(find.text('Installing…'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);

    controller.modelProgress = 0.42;
    controller.notifyListeners();
    await tester.pump();

    await tester.tap(find.text('Pause'));
    await tester.pump();

    expect(controller.isGemmaDownloadPausePending, isTrue);
    expect(find.text('Pausing…'), findsWidgets);
    expect(find.text('Pause'), findsNothing);

    controller.modelPhase = ModelInstallPhase.paused;
    controller.notifyListeners();
    await tester.pump();

    expect(find.textContaining('Paused at'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);

    controller.modelPhase = ModelInstallPhase.ready;
    controller.notifyListeners();
    await tester.pump();

    expect(find.textContaining('Downloading'), findsNothing);
    expect(find.text('Installing…'), findsNothing);
  });

  testWidgets('home shows a published app update and reports a failed install', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    controller.setAvailable(false);
    controller.appUpdatePhase = WorkerAppUpdatePhase.available;
    controller.appUpdateVersionName = '9.9.9';
    controller.appUpdateNotes = 'Faster mission startup';
    controller.appUpdateMandatory = true;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: WorkerHomeTab(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Required app update'), findsOneWidget);
    expect(find.text('Install this update to continue.'), findsOneWidget);
    expect(find.text('Tasks completed'), findsNothing);
    expect(find.text('Version 9.9.9'), findsOneWidget);
    expect(find.text('Faster mission startup'), findsOneWidget);
    expect(find.text('Update app'), findsOneWidget);

    controller.appUpdatePhase = WorkerAppUpdatePhase.downloading;
    controller.appUpdateProgress = 0.4;
    controller.notifyListeners();
    await tester.pump();

    expect(find.text('Downloading update 40%'), findsOneWidget);
    expect(find.text('Update app'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    controller.appUpdatePhase = WorkerAppUpdatePhase.available;
    controller.notifyListeners();
    await tester.pump();

    await tester.tap(find.text('Update app'));
    await tester.pump();

    expect(find.text('App update failed'), findsOneWidget);
    expect(
      find.text('Update details are unavailable. Refresh and try again.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('home updates the model when the published update is a model', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    controller.setAvailable(false);
    controller.modelUpdatePhase = WorkerAppUpdatePhase.available;
    controller.modelUpdateLabel = 'gemma-4-E4B-it.litertlm';
    controller.modelUpdateNotes = 'Refresh the on-device model';
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: WorkerHomeTab(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('App update'), findsNothing);
    expect(find.text('gemma-4-E4B-it.litertlm'), findsNothing);
    expect(find.text('Refresh the on-device model'), findsNothing);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Update app'), findsNothing);

    await tester.tap(find.text('Update'));
    await tester.pump();

    expect(find.text('Update failed'), findsOneWidget);
    expect(
      find.text('Update details are unavailable. Refresh and try again.'),
      findsOneWidget,
    );
  });
}
