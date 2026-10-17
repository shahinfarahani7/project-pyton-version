import 'package:edgemint_worker/ui/tabs/worker_boost_tab.dart';
import 'package:edgemint_worker/ui/worker_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boost tab shows uptime booster panel only', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: const Scaffold(body: WorkerBoostTab()),
      ),
    );

    expect(find.text('Task availability'), findsNothing);
    expect(find.text('Turn availability on'), findsNothing);
    expect(find.text('Uptime Booster'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Activate Booster'), findsOneWidget);
  });
}
