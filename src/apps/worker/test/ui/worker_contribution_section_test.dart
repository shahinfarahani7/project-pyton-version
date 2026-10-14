import 'dart:convert';

import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/api/worker_contribution_models.dart';
import 'package:edgemint_worker/api/worker_routes.dart';
import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/ui/tabs/worker_contribution_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _summaryJson({
  String level = 'silver',
  String? nextLevel = 'gold',
  int total = 120_000,
  int? remaining = 80_000,
  int progressBps = 4667,
  int? acceptedMs = 150_000,
  bool boostActive = false,
  bool purchaseEnabled = false,
  String? blockedReason = 'BOOST_PRICE_NOT_CONFIGURED',
  int? price,
}) =>
    {
      'policyVersion': 'worker-contribution-xp-v1',
      'level': level,
      'nextLevel': nextLevel,
      'totalCentiXp': total,
      'totalXp': formatCentiXp(total),
      'currentLevelMinCentiXp': 50_000,
      'nextLevelMinCentiXp': nextLevel == null ? null : 200_000,
      'remainingCentiXp': remaining,
      'progressBps': progressBps,
      'verifiedTaskCount': 7,
      'acceptedProcessingMs': acceptedMs,
      'boost': {
        'active': boostActive,
        'bonusBps': 2500,
        'expiresAt': boostActive ? '2026-10-14T10:00:00Z' : null,
        'remainingTasks': boostActive ? 12 : null,
      },
      'boostPurchase': {
        'enabled': purchaseEnabled,
        'blockedReason': blockedReason,
        'priceTokenMinorUnits': price,
        'durationHours': 24,
        'taskQuota': 50,
      },
      'scoringStatus': 'ok',
    };

Future<void> _pump(
  WidgetTester tester, {
  WorkerContributionSummary? summary,
  bool loading = false,
  String? error,
  Future<String?> Function()? onActivate,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WorkerContributionSection(
          summary: summary,
          loading: loading,
          error: error,
          activating: false,
          onRetry: () {},
          onActivateBoost: onActivate ?? () async => null,
        ),
      ),
    ),
  );
}

void main() {
  test('parses integer centi-XP and nullable processing time', () {
    final parsed = WorkerContributionSummary.fromJson(_summaryJson(acceptedMs: null));
    expect(parsed.totalCentiXp, 120_000);
    expect(parsed.totalXp, '1200.00');
    expect(parsed.acceptedProcessingMs, isNull);
    expect(parsed.boostPurchase.enabled, isFalse);
    expect(formatCentiXp(1_505), '15.05');
  });

  test('sync call posts with auth and idempotency headers', () async {
    late http.Request captured;
    final client = WorkerApiClient(
      config: WorkerConfig(baseUrl: Uri.parse('http://worker.test')),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_summaryJson()), 200);
      }),
    );
    final summary = await client.syncWorkerContribution(
      accessToken: 'tok',
      idempotencyKey: 'contribution-sync-0001',
    );
    expect(captured.method, 'POST');
    expect(captured.url.path, WorkerRoutes.syncWorkerContribution);
    expect(captured.headers['Authorization'], 'Bearer tok');
    expect(captured.headers['Idempotency-Key'], 'contribution-sync-0001');
    expect(summary.level, 'silver');
  });

  test('boost problem surfaces server code', () async {
    final client = WorkerApiClient(
      config: WorkerConfig(baseUrl: Uri.parse('http://worker.test')),
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'code': 'TOKEN_DEBIT_FAILED'}), 402),
      ),
    );
    expect(
      () => client.activateContributionBoost(accessToken: 'tok', idempotencyKey: 'contribution-boost-1'),
      throwsA(isA<WorkerApiException>().having((e) => e.code, 'code', 'TOKEN_DEBIT_FAILED')),
    );
  });

  testWidgets('shows level, XP, remaining and processing time', (tester) async {
    await _pump(tester, summary: WorkerContributionSummary.fromJson(_summaryJson()));
    expect(find.text('Silver'), findsOneWidget);
    expect(find.text('1200.00 XP'), findsOneWidget);
    expect(find.text('800.00 XP to Gold'), findsOneWidget);
    expect(find.textContaining('2m'), findsOneWidget);
  });

  testWidgets('hides processing time when the server has none', (tester) async {
    await _pump(tester, summary: WorkerContributionSummary.fromJson(_summaryJson(acceptedMs: null)));
    expect(find.text('Accepted processing  '), findsNothing);
    expect(find.textContaining('Accepted processing'), findsNothing);
  });

  testWidgets('platinum shows highest level and no next level', (tester) async {
    await _pump(
      tester,
      summary: WorkerContributionSummary.fromJson(
        _summaryJson(level: 'platinum', nextLevel: null, total: 700_000, remaining: null, progressBps: 10000),
      ),
    );
    expect(find.text('Platinum'), findsOneWidget);
    expect(find.text('Highest contribution level'), findsOneWidget);
    expect(find.textContaining(' XP to '), findsNothing);
  });

  testWidgets('purchase is disabled with a reason when no price is set', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      summary: WorkerContributionSummary.fromJson(_summaryJson()),
      onActivate: () async {
        calls++;
        return null;
      },
    );
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.textContaining('no token price has been set'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('enabled purchase needs confirmation before spending', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      summary: WorkerContributionSummary.fromJson(
        _summaryJson(purchaseEnabled: true, blockedReason: null, price: 300),
      ),
      onActivate: () async {
        calls++;
        return 'TOKEN_DEBIT_FAILED';
      },
    );
    await tester.tap(find.text('Activate · 300 tokens'));
    await tester.pumpAndSettle();
    expect(find.textContaining('spends 300 tokens'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);

    await tester.tap(find.text('Activate · 300 tokens'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spend tokens'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Not enough tokens. Boost was not activated.'), findsOneWidget);
  });

  testWidgets('active boost shows remaining tasks', (tester) async {
    await _pump(tester, summary: WorkerContributionSummary.fromJson(_summaryJson(boostActive: true)));
    expect(find.textContaining('Boost active · 12 tasks left'), findsOneWidget);
  });

  testWidgets('loading and error states', (tester) async {
    await _pump(tester, loading: true);
    expect(find.text('Loading contribution level…'), findsOneWidget);
    await _pump(tester, error: 'HTTP_500');
    expect(find.textContaining('Contribution sync failed on the server'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
