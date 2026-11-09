import 'package:edgemint_worker/runtime/worker_fibonai_earnings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const iran = Duration(hours: 3, minutes: 30);
  final now = DateTime.utc(2026, 11, 3, 6, 30);

  List<double> series(List<({int points, DateTime creditedAtUtc})> credits) {
    return fibonaiDailyPoints(
      credits: credits,
      now: now,
      localOffset: iran,
    );
  }

  test('today and six-day-old credits fill the chart; older credits drop', () {
    final values = series([
      (points: 40, creditedAtUtc: DateTime.utc(2026, 11, 3, 6, 0)),
      (points: 40, creditedAtUtc: DateTime.utc(2026, 11, 2, 21, 0)),
      (points: 40, creditedAtUtc: DateTime.utc(2026, 10, 27, 20, 30)),
      (points: 40, creditedAtUtc: DateTime.utc(2026, 10, 26, 20, 0)),
    ]);

    expect(values, [40, 0, 0, 0, 0, 0, 80]);
  });

  test('server credit history becomes the earnings series', () {
    final values = fibonaiDailyPointsFromBalance(
      {
        'knownDevice': true,
        'points': 80,
        'tasksCompleted': 2,
        'recentCredits': [
          {'points': 40, 'creditedAtUtc': '2026-11-03T06:00:00Z'},
          {'points': 40, 'creditedAtUtc': '2026-10-27T20:30:00Z'},
          {'points': '40', 'creditedAtUtc': '2026-11-03T07:00:00Z'},
        ],
      },
      now: now,
      localOffset: iran,
    );

    expect(values, [40, 0, 0, 0, 0, 0, 40]);
  });

  test('lifetime points land on today when the server has no daily history', () {
    final values = fibonaiDailyPointsFromBalance(
      {'knownDevice': true, 'points': 80, 'tasksCompleted': 2},
      now: now,
      localOffset: iran,
    );

    expect(values, [0, 0, 0, 0, 0, 0, 80]);
    expect(
      fibonaiBalanceOwnsLedger({
        'knownDevice': true,
        'tasksCompleted': 2,
      }),
      isTrue,
    );
  });

  test('unknown device and an empty ledger do not invent earnings', () {
    expect(
      fibonaiDailyPointsFromBalance({'knownDevice': false}, now: now),
      isNull,
    );
    expect(
      fibonaiDailyPointsFromBalance(
        {'knownDevice': true, 'recentCredits': []},
        now: now,
      ),
      emptyFibonaiDailyPoints,
    );
    expect(fibonaiBalanceOwnsLedger({'knownDevice': false}), isFalse);
  });

  test('a local credit adds points to today without erasing earlier days', () {
    final next = addFibonaiPointsToday(
      const [10, 0, 0, 0, 0, 0, 40],
      fibonaiPointsPerCompletedTask,
    );

    expect(next, [10, 0, 0, 0, 0, 0, 40 + fibonaiPointsPerCompletedTask]);
  });

  test('atomic FIBON amounts format without binary fractions', () {
    expect(formatFibonaiAtomic(0), '0 FIBON');
    expect(formatFibonaiAtomic(fibonaiAtomicPerToken), '1 FIBON');
    expect(formatFibonaiAtomic(fibonaiPointsPerCompletedTask), '30 FIBON');
  });
}
