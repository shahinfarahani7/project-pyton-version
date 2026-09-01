import 'package:edgemint_worker/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';

void main() {
  testWidgets('home shows readiness and download action', (tester) async {
    await tester.pumpWidget(const EdgeMintWorkerApp());
    await tester.pumpAndSettle();

    expect(find.text('Ready for missions'), findsOneWidget);
    expect(find.text('Worker availability'), findsOneWidget);
    expect(
      find.textContaining(WorkerModelCatalog.displayName),
      findsAtLeastNWidgets(1),
    );
  });
}
