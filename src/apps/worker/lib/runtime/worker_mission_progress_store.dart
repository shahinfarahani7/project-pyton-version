import 'dart:convert';

import 'encrypted_store.dart';

const _storageKey = 'worker_mission_progress_v1';
const _dailyMissionDayKey = 'worker_daily_mission_day_v1';

/// Local calendar day, `YYYY-MM-DD`. The daily mission resets after midnight.
String workerLocalCalendarDay(DateTime now) {
  final local = now.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

/// Local acknowledgments only — server mission tracking remains authoritative.
class WorkerMissionProgressStore {
  WorkerMissionProgressStore(this._store);

  final EncryptedStore _store;

  Future<Set<String>> readCompletedMissionIds() async {
    final bytes = await _store.read(_storageKey);
    if (bytes == null || bytes.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List) {
      return {};
    }
    return decoded.map((e) => e.toString()).toSet();
  }

  Future<void> writeCompletedMissionIds(Set<String> ids) async {
    await _store.write(
      _storageKey,
      utf8.encode(jsonEncode(ids.toList()..sort())),
    );
  }

  Future<String?> readDailyMissionDay() async {
    final bytes = await _store.read(_dailyMissionDayKey);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(decoded)) {
      return null;
    }
    return decoded;
  }

  Future<void> writeDailyMissionDay(String day) async {
    await _store.write(_dailyMissionDayKey, utf8.encode(jsonEncode(day)));
  }
}
