import 'package:edgemint_worker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows readiness and download action', (tester) async {
    await tester.pumpWidget(const EdgeMintWorkerApp());
    expect(find.text('Ready for missions'), findsOneWidget);
    expect(find.text('Device readiness'), findsOneWidget);
    expect(find.text('Download Gemma model'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Earnings summary'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Earnings summary'), findsOneWidget);
  });
}
