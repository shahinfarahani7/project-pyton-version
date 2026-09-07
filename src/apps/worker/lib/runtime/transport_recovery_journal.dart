import 'dart:convert';

/// Persisted outbound transport message eligible for idempotent retransmission.
///
/// Retransmitting a journal entry is transport recovery only; it MUST NOT rerun
/// inference or create a new Task attempt (Architecture v2 §2.4).
class TransportJournalEntry {
  const TransportJournalEntry({
    required this.assignmentId,
    required this.eventKind,
    required this.idempotencyKey,
    required this.path,
    required this.bodyJson,
    required this.recordedAt,
    this.acknowledged = false,
  });

  final String assignmentId;
  final String eventKind;
  final String idempotencyKey;
  final String path;
  final String bodyJson;
  final DateTime recordedAt;
  final bool acknowledged;

  Map<String, dynamic> toJson() => {
        'assignmentId': assignmentId,
        'eventKind': eventKind,
        'idempotencyKey': idempotencyKey,
        'path': path,
        'bodyJson': bodyJson,
        'recordedAt': recordedAt.toIso8601String(),
        'acknowledged': acknowledged,
      };

  factory TransportJournalEntry.fromJson(Map<String, dynamic> json) =>
      TransportJournalEntry(
        assignmentId: json['assignmentId'] as String,
        eventKind: json['eventKind'] as String,
        idempotencyKey: json['idempotencyKey'] as String,
        path: json['path'] as String,
        bodyJson: json['bodyJson'] as String,
        recordedAt: DateTime.parse(json['recordedAt'] as String),
        acknowledged: json['acknowledged'] as bool? ?? false,
      );

  TransportJournalEntry copyWith({bool? acknowledged}) => TransportJournalEntry(
        assignmentId: assignmentId,
        eventKind: eventKind,
        idempotencyKey: idempotencyKey,
        path: path,
        bodyJson: bodyJson,
        recordedAt: recordedAt,
        acknowledged: acknowledged ?? this.acknowledged,
      );
}

typedef TransportRetransmitFn = Future<void> Function(TransportJournalEntry entry);

/// In-memory transport journal for bounded retransmission without rerunning inference.
class TransportRecoveryJournal {
  TransportRecoveryJournal({TransportRetransmitFn? retransmit});

  final List<TransportJournalEntry> _entries = [];
  TransportRetransmitFn? _retransmit;

  List<TransportJournalEntry> get pendingEntries =>
      List.unmodifiable(_entries.where((entry) => !entry.acknowledged));

  void bindRetransmit(TransportRetransmitFn retransmit) {
    _retransmit = retransmit;
  }

  void record(TransportJournalEntry entry) {
    final existingIndex = _entries.indexWhere(
      (candidate) =>
          candidate.assignmentId == entry.assignmentId &&
          candidate.idempotencyKey == entry.idempotencyKey,
    );
    if (existingIndex >= 0) {
      _entries[existingIndex] = entry;
      return;
    }
    _entries.add(entry);
  }

  void acknowledge(String idempotencyKey) {
    for (var index = 0; index < _entries.length; index += 1) {
      final entry = _entries[index];
      if (entry.idempotencyKey == idempotencyKey) {
        _entries[index] = entry.copyWith(acknowledged: true);
      }
    }
  }

  Future<int> retransmitPending() async {
    final sender = _retransmit;
    if (sender == null) {
      return 0;
    }
    var count = 0;
    for (final entry in pendingEntries) {
      await sender(entry);
      count += 1;
    }
    return count;
  }

  String serialize() => jsonEncode(_entries.map((entry) => entry.toJson()).toList());

  void restore(String serialized) {
    _entries
      ..clear()
      ..addAll(
        (jsonDecode(serialized) as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(TransportJournalEntry.fromJson),
      );
  }
}
