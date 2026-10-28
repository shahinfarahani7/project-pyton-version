import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/execution_status.dart';
import 'package:edgemint_worker/ui/tabs/worker_home_tab.dart';
import 'package:edgemint_worker/ui/worker_theme.dart';
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
      expect(find.text('0'), findsNWidgets(2));
      expect(find.text(r'$0.00'), findsNothing);
      controller.tasksProcessed = 2;
      controller.notifyListeners();
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
      expect(find.text('AI model'), findsNothing);
      expect(find.text('Download model'), findsNothing);
      expect(find.textContaining('Qwen'), findsNothing);
      expect(find.text('Earnings'), findsOneWidget);
      expect(find.textContaining('not guaranteed'), findsWidgets);
      expect(find.text('Boost your worker'), findsNothing);
      expect(find.text('Turn availability on'), findsNothing);
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

    expect(find.text('Installing model…'), findsOneWidget);
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
    expect(find.text('Installing model…'), findsNothing);
  });
}
