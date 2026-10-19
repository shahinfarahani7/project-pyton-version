import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/ui/tabs/worker_missions_tab.dart';
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

    expect(find.text('Daily online'), findsOneWidget);
    expect(find.text('Join Telegram'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Open Telegram'), findsNothing);
    expect(find.text('10 pts / verified day'), findsOneWidget);
    expect(find.text('25 pts (one-time)'), findsNWidgets(3));
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

    expect(find.byKey(const ValueKey('mission-check-social_telegram')), findsOneWidget);
    final check = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('mission-check-social_telegram')),
        matching: find.byType(Icon),
      ),
    );
    expect(check.icon, Icons.check_box_rounded);
    expect(find.widgetWithText(TextButton, 'Open Telegram'), findsNothing);
  });

  testWidgets('help button opens how to complete dialog', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
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

    await tester.tap(find.byKey(const ValueKey('mission-help-social_telegram')));
    await tester.pumpAndSettle();
    expect(find.text('How to complete'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Open Telegram'), findsOneWidget);
  });

  testWidgets('wallet mission help shows instructions without payout link', (
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
        home: Scaffold(
          body: WorkerMissionsTab(controller: controller),
        ),
      ),
    );

    expect(find.widgetWithText(TextButton, 'Open payout wallet setup'), findsNothing);

    final walletHelp = find.byKey(const ValueKey('mission-help-define_wallet'));
    await tester.scrollUntilVisible(walletHelp, 300);
    await tester.tap(walletHelp);
    await tester.pumpAndSettle();

    expect(find.text('How to complete'), findsOneWidget);
    expect(find.textContaining('Earnings tab'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Open payout wallet setup'), findsNothing);
  });
}
