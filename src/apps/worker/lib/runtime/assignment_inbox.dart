import 'dart:convert';
import 'dart:typed_data';

import '../api/worker_assignment_models.dart';
import 'encrypted_store.dart';

enum AssignmentInboxDisposition {
  accepted,
  duplicateReplay,
  staleFenceSuperseded,
}

class AssignmentInboxEntry {
  AssignmentInboxEntry({
    required this.assignmentId,
    required this.attemptId,
    required this.fenceToken,
    required this.recordedAt,
    this.ackedAt,
    this.deliveryInboxId,
  });

  final String assignmentId;
  final String attemptId;
  final int fenceToken;
  final DateTime recordedAt;
  final DateTime? ackedAt;
  final String? deliveryInboxId;

  Map<String, dynamic> toJson() => {
        'assignmentId': assignmentId,
        'attemptId': attemptId,
        'fenceToken': fenceToken,
        'recordedAt': recordedAt.toIso8601String(),
        if (ackedAt != null) 'ackedAt': ackedAt!.toIso8601String(),
        if (deliveryInboxId != null) 'deliveryInboxId': deliveryInboxId,
      };

  factory AssignmentInboxEntry.fromJson(Map<String, dynamic> json) => AssignmentInboxEntry(
        assignmentId: json['assignmentId'] as String,
        attemptId: json['attemptId'] as String,
        fenceToken: json['fenceToken'] as int,
        recordedAt: DateTime.parse(json['recordedAt'] as String),
        ackedAt: json['ackedAt'] == null ? null : DateTime.parse(json['ackedAt'] as String),
        deliveryInboxId: json['deliveryInboxId'] as String?,
      );
}

class AssignmentInboxReceipt {
  const AssignmentInboxReceipt({
    required this.disposition,
    required this.entry,
  });

  final AssignmentInboxDisposition disposition;
  final AssignmentInboxEntry entry;
}

/// Local durable inbox for assignment deliveries before execution (v2 §7, §39, A03).
class AssignmentInbox {
  AssignmentInbox({
    required EncryptedStore store,
    DateTime Function()? clock,
    this.storageKey = 'assignment_inbox_v1',
  })  : _store = store,
        _clock = clock ?? DateTime.now;

  final EncryptedStore _store;
  final DateTime Function() _clock;
  final String storageKey;

  Future<AssignmentInboxReceipt> recordBeforeProcess(
    WorkerAssignment assignment, {
    String? deliveryInboxId,
  }) async {
    final entries = await _loadEntries();
    final existing = entries.where((item) => item.assignmentId == assignment.assignmentId).toList()
      ..sort((a, b) => b.fenceToken.compareTo(a.fenceToken));
    if (existing.isNotEmpty) {
      final latest = existing.first;
      if (latest.fenceToken == assignment.fenceToken) {
        return AssignmentInboxReceipt(
          disposition: AssignmentInboxDisposition.duplicateReplay,
          entry: latest,
        );
      }
      if (latest.fenceToken > assignment.fenceToken) {
        return AssignmentInboxReceipt(
          disposition: AssignmentInboxDisposition.staleFenceSuperseded,
          entry: latest,
        );
      }
    }

    final entry = AssignmentInboxEntry(
      assignmentId: assignment.assignmentId,
      attemptId: assignment.attemptId,
      fenceToken: assignment.fenceToken,
      recordedAt: _clock(),
      deliveryInboxId: deliveryInboxId,
    );
    entries.removeWhere((item) => item.assignmentId == assignment.assignmentId);
    entries.add(entry);
    await _persist(entries);
    return AssignmentInboxReceipt(
      disposition: AssignmentInboxDisposition.accepted,
      entry: entry,
    );
  }

  Future<void> markAcked(String assignmentId, {required int fenceToken}) async {
    final entries = await _loadEntries();
    var changed = false;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.assignmentId == assignmentId && entry.fenceToken == fenceToken) {
        entries[i] = AssignmentInboxEntry(
          assignmentId: entry.assignmentId,
          attemptId: entry.attemptId,
          fenceToken: entry.fenceToken,
          recordedAt: entry.recordedAt,
          ackedAt: _clock(),
          deliveryInboxId: entry.deliveryInboxId,
        );
        changed = true;
      }
    }
    if (changed) {
      await _persist(entries);
    }
  }

  Future<List<AssignmentInboxEntry>> reconcileBootstrap({
    required Iterable<AssignmentInboxEntry> serverEntries,
  }) async {
    final local = await _loadEntries();
    final merged = <String, AssignmentInboxEntry>{
      for (final entry in local) '${entry.assignmentId}|${entry.fenceToken}': entry,
    };
    for (final serverEntry in serverEntries) {
      final key = '${serverEntry.assignmentId}|${serverEntry.fenceToken}';
      merged.putIfAbsent(key, () => serverEntry);
    }
    final result = merged.values.toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    await _persist(result);
    return result;
  }

  Future<List<AssignmentInboxEntry>> pendingEntries() async {
    final entries = await _loadEntries();
    return entries.where((entry) => entry.ackedAt == null).toList(growable: false);
  }

  Future<List<AssignmentInboxEntry>> _loadEntries() async {
    final bytes = await _store.read(storageKey);
    if (bytes == null) {
      return [];
    }
    final decoded = jsonDecode(utf8.decode(bytes)) as List<dynamic>;
    return decoded
        .map((item) => AssignmentInboxEntry.fromJson(item as Map<String, dynamic>))
        .toList(growable: true);
  }

  Future<void> _persist(List<AssignmentInboxEntry> entries) async {
    final payload = utf8.encode(jsonEncode(entries.map((entry) => entry.toJson()).toList()));
    await _store.write(storageKey, Uint8List.fromList(payload));
  }
}
