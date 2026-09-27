import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/ui/tabs/worker_home_tab.dart';
import 'package:edgemint_worker/ui/worker_theme.dart';
import 'package:edgemint_worker/worker_app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows readiness and download action', (tester) async {
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

    expect(find.text('Ready for missions'), findsOneWidget);
    expect(find.text('Worker availability'), findsOneWidget);
    expect(
      find.textContaining(WorkerModelCatalog.displayName),
      findsAtLeastNWidgets(1),
    );
  });
}
