import 'dart:convert';

import 'encrypted_store.dart';

const _storageKey = 'worker_mission_progress_v1';

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
}
