import 'package:edgemint_worker/ui/tabs/worker_uptime_section.dart';
import 'package:edgemint_worker/ui/worker_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkerUptimeProgress _fixture({
  bool active = true,
  String level = 'silver',
  String? next = 'gold',
  int? remaining = 100800000,
}) => WorkerUptimeProgress(
  level: level,
  nextLevel: next,
  actualUptimeMs: 130800000,
  boosterBonusMs: 27600000,
  creditedLevelTimeMs: 158400000,
  remainingLevelTimeMs: remaining,
  progressBps: next == null ? 10000 : 4167,
  boosterActive: active,
  boosterMultiplierBps: 20000,
  boosterExpiresAt: active ? DateTime.utc(2026, 10, 15, 11) : null,
  boosterUnavailableReason: 'Contributor tokens are not connected.',
);

Future<void> _pump(
  WidgetTester tester, {
  WorkerUptimeProgress? data,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWorkerTheme(),
      home: Scaffold(body: WorkerUptimeDashboardSection(uptime: data)),
    ),
  );
}

void main() {
  test('formats integer durations and Booster rates without inventing XP', () {
    expect(formatMissionTime(158400000), '44h 00m');
    expect(formatMissionMultiplier(20000), '2×');
    expect(formatMissionMultiplier(15000), '1.5×');
  });

  testWidgets('dashboard shows uptime breakdown when data is supplied', (
    tester,
  ) async {
    await _pump(tester, data: _fixture());
    expect(find.text('Silver'), findsOneWidget);
    expect(find.text('44h 00m'), findsOneWidget);
    expect(find.textContaining('36h 20m'), findsOneWidget);
    expect(find.textContaining('+7h 40m'), findsOneWidget);
    expect(find.text('28h 00m level time to Gold'), findsOneWidget);
    expect(find.textContaining('2× level progress'), findsOneWidget);
    expect(find.textContaining('XP'), findsNothing);
  });

  testWidgets('no server data is not zero uptime or a fabricated Bronze rank', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Uptime progress is not connected yet.'), findsOneWidget);
    expect(find.text('0h 00m'), findsNothing);
    expect(find.text('Bronze'), findsNothing);
  });

  testWidgets('Booster purchase stays disabled when inactive', (tester) async {
    await _pump(tester, data: _fixture(active: false));
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Activate Booster'),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Activate Booster'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('Platinum does not invent a fifth level', (tester) async {
    await _pump(
      tester,
      data: _fixture(level: 'platinum', next: null, remaining: null),
    );
    expect(find.text('Highest contribution level'), findsOneWidget);
    expect(find.textContaining('level time to'), findsNothing);
  });

  testWidgets('mobile and desktop layout does not overflow', (tester) async {
    for (final width in [360.0, 390.0, 1440.0]) {
      await _pump(tester, data: _fixture(), width: width);
      expect(tester.takeException(), isNull);
    }
  });
}
