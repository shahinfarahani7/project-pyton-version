import 'package:edgemint_worker/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows readiness and download action', (tester) async {
    await tester.pumpWidget(const EdgeMintWorkerApp());
    expect(find.text('Ready for missions'), findsOneWidget);
    expect(find.text('Device readiness'), findsOneWidget);
    expect(find.textContaining('Qwen3'), findsOneWidget);
  });
}
