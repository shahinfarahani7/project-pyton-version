/// Fibonai points credited for one successfully completed task.
const fibonaiPointsPerCompletedTask = 40;

const fibonaiChartDays = 7;

const emptyFibonaiDailyPoints = <double>[0, 0, 0, 0, 0, 0, 0];

/// Points earned on each of the last [fibonaiChartDays] local days.
///
/// Index 0 is the oldest day and the last index is [now]'s local date.
/// Credits older than the window are omitted. Same-day credits are summed.
List<double> fibonaiDailyPoints({
  required Iterable<({int points, DateTime creditedAtUtc})> credits,
  required DateTime now,
  Duration? localOffset,
}) {
  final today = _civilDay(now, localOffset);
  final totals = List<double>.from(emptyFibonaiDailyPoints);
  for (final credit in credits) {
    if (credit.points <= 0) {
      continue;
    }
    final day = _civilDay(credit.creditedAtUtc, localOffset);
    final age = _calendarDaysBetween(day, today);
    final index = fibonaiChartDays - 1 - age;
    if (index < 0 || index >= fibonaiChartDays) {
      continue;
    }
    totals[index] += credit.points.toDouble();
  }
  return totals;
}

DateTime _civilDay(DateTime instant, Duration? localOffset) {
  final shifted = localOffset == null
      ? instant.toLocal()
      : instant.toUtc().add(localOffset);
  return DateTime.utc(shifted.year, shifted.month, shifted.day);
}

int _calendarDaysBetween(DateTime earlierDay, DateTime laterDay) {
  return laterDay.difference(earlierDay).inDays;
}

/// Builds the home-chart series from a Fibonai balance payload.
///
/// Returns null when the payload is not a known-device balance. A balance
/// that lists [recentCredits] uses those timestamps. Older servers that only
/// return a lifetime [points] total place that total on today so the chart
/// is not left empty.
List<double>? fibonaiDailyPointsFromBalance(
  Map<dynamic, dynamic> balance, {
  required DateTime now,
  Duration? localOffset,
}) {
  if (balance['knownDevice'] != true) {
    return null;
  }
  final recent = balance['recentCredits'];
  if (recent is List) {
    return fibonaiDailyPoints(
      credits: _creditsFromJson(recent),
      now: now,
      localOffset: localOffset,
    );
  }
  final points = _asInt(balance['points']);
  if (points != null && points > 0) {
    return addFibonaiPointsToday(emptyFibonaiDailyPoints, points);
  }
  final tasks = _asInt(balance['tasksCompleted']);
  if (tasks != null && tasks > 0) {
    final perTask =
        _asInt(balance['pointsPerTask']) ?? fibonaiPointsPerCompletedTask;
    return addFibonaiPointsToday(emptyFibonaiDailyPoints, tasks * perTask);
  }
  return List<double>.from(emptyFibonaiDailyPoints);
}

/// Whether this payload is the server ledger, so the device must not also
/// add a local credit for the same completed task.
bool fibonaiBalanceOwnsLedger(Map<dynamic, dynamic> balance) {
  if (balance['knownDevice'] != true) {
    return false;
  }
  final tasks = _asInt(balance['tasksCompleted']);
  if (tasks != null && tasks >= 0) {
    return true;
  }
  return balance['recentCredits'] is List;
}

List<double> addFibonaiPointsToday(List<double> current, int points) {
  final values = current.length == fibonaiChartDays
      ? List<double>.from(current)
      : List<double>.from(emptyFibonaiDailyPoints);
  if (points > 0) {
    values[values.length - 1] += points.toDouble();
  }
  return values;
}

Iterable<({int points, DateTime creditedAtUtc})> _creditsFromJson(
  List<dynamic> recent,
) sync* {
  for (final item in recent) {
    if (item is! Map) {
      continue;
    }
    final points = _asInt(item['points']);
    final rawTime = item['creditedAtUtc'];
    if (points == null || rawTime is! String) {
      continue;
    }
    final creditedAt = DateTime.tryParse(rawTime);
    if (creditedAt == null) {
      continue;
    }
    yield (points: points, creditedAtUtc: creditedAt.toUtc());
  }
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double && value.isFinite && value == value.roundToDouble()) {
    return value.round();
  }
  return null;
}
