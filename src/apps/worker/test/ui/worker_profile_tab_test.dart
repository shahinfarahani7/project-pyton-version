import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/worker_account_profile_store.dart';
import 'package:edgemint_worker/ui/tabs/worker_profile_tab.dart';
import 'package:edgemint_worker/ui/worker_theme.dart';
import 'package:edgemint_worker/worker_app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profile shows read-only username and email', (tester) async {
    final store = InMemoryEncryptedStore();
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: store,
    );
    addTearDown(controller.dispose);

    await WorkerAccountProfileStore(store).write(
      WorkerAccountProfile(
        username: 'fibon_worker',
        email: 'worker@example.com',
        updatedAtUtc: DateTime.utc(2026, 1, 1),
      ),
    );
    await controller.loadAccountProfile();

    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Scaffold(
            body: WorkerProfileTab(controller: controller),
          ),
        ),
      ),
    );

    expect(find.text('Account'), findsWidgets);
    expect(find.text('fibon_worker'), findsOneWidget);
    expect(find.textContaining('w•••@example.com'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Connection'), findsNothing);
    expect(find.text('Models on device'), findsNothing);
  });

  testWidgets('profile shows placeholders when account profile is empty', (
    tester,
  ) async {
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: Scaffold(body: WorkerProfileTab(controller: controller)),
      ),
    );

    expect(find.text('Not set'), findsNWidgets(2));
  });

  test('requestPasswordChange does not pretend server success', () async {
    final controller = WorkerAppController(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:65535')),
      encryptedStore: InMemoryEncryptedStore(),
    );
    addTearDown(controller.dispose);

    final message = await controller.requestPasswordChange(
      currentPassword: 'current-password',
      newPassword: 'new-long-password',
      confirmPassword: 'new-long-password',
    );
    expect(message, contains('not connected'));
  });
}
