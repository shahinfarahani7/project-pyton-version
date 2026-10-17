import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/worker_payout_wallet_store.dart';
import 'package:edgemint_worker/ui/tabs/worker_earnings_tab.dart';
import 'package:edgemint_worker/ui/worker_theme.dart';
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
          builder: (context, _) => Scaffold(body: WorkerEarningsTab(controller: controller)),
        ),
      ),
    );

    expect(find.text('No payout wallet yet. Add one to prepare for rewards.'), findsOneWidget);
    expect(find.text('Add wallet'), findsOneWidget);

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
