import 'dart:convert';
import 'dart:typed_data';

import 'encrypted_store.dart';

/// Durable outbox for assignment complete payloads awaiting server ACK.
class ResultSubmissionOutbox {
  ResultSubmissionOutbox({required EncryptedStore store, this.storageKey = 'result_outbox_v1'});

  final EncryptedStore _store;
  final String storageKey;

  Future<void> enqueue(String idempotencyKey, Map<String, dynamic> payload) async {
    final entries = await _load();
    entries[idempotencyKey] = payload;
    await _persist(entries);
  }

  Future<Map<String, Map<String, dynamic>>> pending() => _load();

  Future<void> ack(String idempotencyKey) async {
    final entries = await _load();
    entries.remove(idempotencyKey);
    await _persist(entries);
  }

  Future<Map<String, Map<String, dynamic>>> _load() async {
    final bytes = await _store.read(storageKey);
    if (bytes == null) {
      return {};
    }
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return decoded.map(
      (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
    );
  }

  Future<void> _persist(Map<String, Map<String, dynamic>> entries) async {
    await _store.write(
      storageKey,
      Uint8List.fromList(utf8.encode(jsonEncode(entries))),
    );
  }
}
