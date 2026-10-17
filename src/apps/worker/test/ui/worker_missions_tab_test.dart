import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/ui/tabs/worker_missions_tab.dart';
import 'package:edgemint_worker/ui/worker_nav_index.dart';
import 'package:edgemint_worker/ui/worker_theme.dart';
import 'package:edgemint_worker/worker_app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('missions tab lists catalog missions with daily online first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Scaffold(
            body: WorkerMissionsTab(controller: controller),
          ),
        ),
      ),
    );

    expect(find.text('Uptime progress is not connected yet.'), findsOneWidget);
    expect(find.text('Daily online'), findsOneWidget);
    expect(find.text('Join Telegram'), findsWidgets);
    expect(find.text('View uptime on Home'), findsNothing);
    expect(find.text('Follow Discord'), findsWidgets);
    expect(find.text('Follow Twitter'), findsWidgets);
    expect(find.text('Set up your payout wallet'), findsOneWidget);

    final daily = tester.getTopLeft(find.text('Daily online').first);
    final telegram = tester.getTopLeft(find.text('Join Telegram').first);
    expect(daily.dy, lessThan(telegram.dy));
  });

  testWidgets('acknowledged social mission shows completed disabled button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(controller.dispose);
    await controller.acknowledgeMission('social_telegram');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Scaffold(
            body: WorkerMissionsTab(controller: controller),
          ),
        ),
      ),
    );

    final completed = find.widgetWithText(FilledButton, 'Completed');
    expect(completed, findsWidgets);
    final button = tester.widget<FilledButton>(completed.first);
    expect(button.onPressed, isNull);
  });

  testWidgets('wallet mission opens earnings tab when navigation is wired', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = WorkerNavIndex.missions;
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: Scaffold(
          body: WorkerMissionsTab(
            controller: controller,
            onNavigate: (index) => selected = index,
          ),
        ),
      ),
    );

    final walletLink = find.widgetWithText(
      TextButton,
      'Open payout wallet setup',
    );
    await tester.scrollUntilVisible(walletLink, 300);
    final button = tester.widget<TextButton>(walletLink);
    expect(button.onPressed, isNotNull);
    button.onPressed!();
    expect(selected, WorkerNavIndex.earnings);
  });
}
