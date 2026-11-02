import 'package:edgemint_worker/ui/fibonai_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('splash draws the FibonAI mark and finishes the stroke', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FibonaiSplashScreen(onFinished: () => finished = true),
      ),
    );

    expect(find.bySemanticsLabel('FibonAI logo'), findsOneWidget);
    expect(finished, isFalse);

    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump();

    expect(finished, isTrue);
    expect(find.bySemanticsLabel('FibonAI logo'), findsOneWidget);
  });

  test('mark paths cover the curved block and the bar', () {
    final left = FibonaiMarkPaths.leftShape().getBounds();
    final bar = FibonaiMarkPaths.bar().getBounds();
    expect(left.width, greaterThan(60));
    expect(left.height, greaterThan(80));
    expect(bar.left, greaterThan(left.right));
    expect(bar.height, greaterThan(80));
  });
}
