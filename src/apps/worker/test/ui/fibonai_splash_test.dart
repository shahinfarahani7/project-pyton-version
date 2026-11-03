import 'dart:ui' as ui;

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

  test('frames span the mark box and the gold sits inside the upper frame', () {
    const box = Rect.fromLTWH(
      0,
      0,
      FibonaiMarkPaths.viewWidth,
      FibonaiMarkPaths.viewHeight,
    );
    final lower = FibonaiMarkPaths.lowerFrame().getBounds();
    final upper = FibonaiMarkPaths.upperFrame().getBounds();
    final quarter = FibonaiMarkPaths.goldQuarter().getBounds();
    final bar = FibonaiMarkPaths.goldBar().getBounds();
    final half = FibonaiMarkPaths.frameWidth / 2;

    expect(lower.inflate(half).left, closeTo(box.left, 0.5));
    expect(lower.inflate(half).bottom, closeTo(box.bottom, 0.5));
    expect(upper.inflate(half).right, closeTo(box.right, 0.5));
    expect(upper.inflate(half).top, closeTo(box.top, 0.5));

    for (final gold in [quarter, bar]) {
      expect(gold.left, greaterThan(upper.left));
      expect(gold.right, lessThan(upper.right));
      expect(gold.top, greaterThan(upper.top));
      expect(gold.bottom, lessThan(upper.bottom));
    }
    expect(bar.left, greaterThan(quarter.right));
  });

  test('upper frame is one stroke and the top cut only trims the arc start', () {
    final upper = FibonaiMarkPaths.upperFrame().computeMetrics().toList();
    expect(upper, hasLength(1));
    final metric = upper.single;
    final cut = FibonaiMarkPaths.innerArcTopCut;

    expect(cut.contains(metric.getTangentForOffset(0)!.position), isTrue);
    for (var offset = 0.0; offset <= metric.length; offset += 2) {
      final point = metric.getTangentForOffset(offset)!.position;
      if (cut.contains(point)) {
        expect(offset, lessThan(15), reason: 'cut reaches $point');
      }
    }
  });

  test('painter draws at every stage without throwing', () {
    for (final progress in [0.0, 0.3, 0.6, 0.9, 1.0]) {
      final recorder = ui.PictureRecorder();
      FibonaiMarkPainter(progress: progress).paint(
        Canvas(recorder),
        const Size.square(200),
      );
      recorder.endRecording().dispose();
    }
  });
}
