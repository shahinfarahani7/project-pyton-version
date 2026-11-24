import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/worker_fibonai_earnings.dart';
import 'package:edgemint_worker/runtime/worker_payout_wallet_store.dart';
import 'package:edgemint_worker/ui/tabs/worker_earnings_tab.dart';
import 'package:edgemint_worker/ui/worker_theme.dart';
import 'package:edgemint_worker/ui/worker_widgets.dart';
import 'package:edgemint_worker/worker_app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('earnings tab lists saved payout wallets', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(controller.dispose);
    await controller.loadPayoutWallets();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: ListenableBuilder(
          listenable: controller,
          builder: (context, _) =>
              Scaffold(body: WorkerEarningsTab(controller: controller)),
        ),
      ),
    );

    expect(
      find.text('No payout wallet yet. Add one to prepare for rewards.'),
      findsOneWidget,
    );
    expect(find.text('Add wallet'), findsOneWidget);
    expect(find.text('0 FIBON'), findsOneWidget);
    expect(find.textContaining('€'), findsNothing);
    expect(find.textContaining('EUR'), findsNothing);
    expect(
      find.text(
        'Where Fibon rewards should be sent. Saved encrypted on this device until server registration is connected.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<WorkerLineChart>(find.byType(WorkerLineChart)).values,
      const [0, 0, 0, 0, 0, 0, 0],
    );
    expect(
      tester.getTopLeft(find.text('Earnings')).dy,
      greaterThan(tester.getTopLeft(find.text('Payout wallets')).dy),
    );

    controller.tasksProcessed = 2;
    controller.fibonaiDailyPoints = const [0, 0, 0, 0, 40, 0, 40];
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('60 FIBON'), findsOneWidget);
    expect(
      tester.widget<WorkerLineChart>(find.byType(WorkerLineChart)).values,
      const [0, 0, 0, 0, 40, 0, 40],
    );
    expect(
      find.textContaining('80 Fibonai over the last 7 days'),
      findsOneWidget,
    );

    controller.fibonaiBalanceFromServer = true;
    controller.fibonaiBalanceAtomic = fibonaiAtomicPerToken;
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('1 FIBON'), findsOneWidget);

    await controller.addPayoutWallet(
      kind: WorkerPayoutWalletKind.cryptoUsdtTrc20,
      destination: 'T123456789012345678901234567890',
      label: 'Main wallet',
    );
    await tester.pump();

    expect(find.text('Main wallet'), findsOneWidget);
    expect(find.text('Device only'), findsOneWidget);
    expect(find.textContaining('T123'), findsOneWidget);
  });

  test('addPayoutWallet rejects short destinations', () async {
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(controller.dispose);
    final error = await controller.addPayoutWallet(
      kind: WorkerPayoutWalletKind.cryptoUsdtTrc20,
      destination: 'short',
      label: 'Test',
    );
    expect(error, isNotNull);
    expect(controller.payoutWallets, isEmpty);
  });
}
