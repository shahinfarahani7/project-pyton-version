import 'dart:convert';

import 'encrypted_store.dart';

const _storageKey = 'worker_fibonai_credits_v1';

/// Device-local record of assignments already credited in the worker panel.
class WorkerFibonaiCreditStore {
  WorkerFibonaiCreditStore(this._store);

  final EncryptedStore _store;

  Future<Set<String>> readCreditedAssignmentIds() async {
    final bytes = await _store.read(_storageKey);
    if (bytes == null || bytes.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List) {
      return {};
    }
    return decoded.map((item) => item.toString()).where((id) => id.isNotEmpty).toSet();
  }

  Future<void> writeCreditedAssignmentIds(Set<String> ids) async {
    await _store.write(
      _storageKey,
      utf8.encode(jsonEncode(ids.toList()..sort())),
    );
  }
}
