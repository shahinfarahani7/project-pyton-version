import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/execution_status.dart';
import 'package:edgemint_worker/ui/tabs/worker_home_tab.dart';
import 'package:edgemint_worker/ui/worker_theme.dart';
import 'package:edgemint_worker/worker_app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows the character, earnings chart, and boost prompt', (tester) async {
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    controller.setAvailable(false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: WorkerHomeTab(
          controller: controller,
          onDownloadModel: () {},
          onAvailabilityChanged: controller.setAvailable,
          onNavigate: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Worker character waiting for a task'), findsOneWidget);
    expect(find.text('Tasks completed'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text(r'$0.00'), findsOneWidget);
    expect(find.text('Earnings'), findsOneWidget);
    expect(find.textContaining('not guaranteed'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Turn availability on'), 200);
    expect(find.text('Boost your worker'), findsOneWidget);
    expect(find.text('Turn availability on'), findsOneWidget);
  });

  testWidgets('home shows the running character while a task is active', (tester) async {
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    controller.setAvailable(false);
    controller.executionStatus = const ExecutionStatus(phase: ExecutionPhase.running);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: WorkerHomeTab(
          controller: controller,
          onDownloadModel: () {},
          onAvailabilityChanged: controller.setAvailable,
          onNavigate: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Worker character running a task'), findsOneWidget);
    expect(find.bySemanticsLabel('Worker character waiting for a task'), findsNothing);
  });
}
