import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/execution_status.dart';
import 'package:edgemint_worker/runtime/worker_app_update.dart';
import 'package:edgemint_worker/ui/gemma_download_dialog.dart';
import 'package:edgemint_worker/ui/tabs/worker_home_tab.dart';
import 'package:edgemint_worker/ui/worker_theme.dart';
import 'package:edgemint_worker/ui/worker_widgets.dart';
import 'package:edgemint_worker/worker_app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'home shows the character and Fibonai total without the earnings chart',
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

      expect(find.bySemanticsLabel('FibonAI mascot resting'), findsOneWidget);
      expect(find.text('Tasks completed'), findsOneWidget);
      expect(find.text('Fibonai'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('0 FIBON'), findsOneWidget);
      expect(find.text(r'$0.00'), findsNothing);
      expect(find.text('Earnings'), findsNothing);
      expect(find.byType(WorkerLineChart), findsNothing);
      controller.tasksProcessed = 2;
      controller.notifyListeners();
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
      expect(find.text('60 FIBON'), findsOneWidget);
      expect(find.text('AI model'), findsNothing);
      expect(find.text('Download model'), findsNothing);
      expect(find.textContaining('Qwen'), findsNothing);
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
      find.bySemanticsLabel('FibonAI mascot running a task'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('FibonAI mascot resting'), findsNothing);
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

  testWidgets('model download progress stays visible during a required app update', (
    tester,
  ) async {
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    controller.setAvailable(false);
    controller.appUpdatePhase = WorkerAppUpdatePhase.available;
    controller.appUpdateVersionName = '9.9.9';
    controller.appUpdateMandatory = true;
    controller.modelPhase = ModelInstallPhase.downloading;
    controller.modelProgress = 0.2;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: WorkerHomeTab(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Required app update'), findsOneWidget);
    expect(find.text('Downloading 20%'), findsOneWidget);
  });

  testWidgets('missing model dialog asks to download Gemma', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () {
                showModelUpdatePromptDialog(context);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('Download ${WorkerModelCatalog.displayName}'),
      findsOneWidget,
    );
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
  });

  testWidgets('home offers a Google Play update', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    controller.setAvailable(false);
    controller.appUpdateFromPlay = true;
    controller.appUpdatePhase = WorkerAppUpdatePhase.available;
    controller.appUpdateMandatory = true;
    controller.appUpdateNotes = 'Google Play will install build 40105.';
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: WorkerHomeTab(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Google Play'), findsOneWidget);
    expect(find.text('Update with Google Play'), findsOneWidget);
    expect(find.text('Google Play will install build 40105.'), findsOneWidget);
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
