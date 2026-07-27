import 'dart:convert';
import 'dart:typed_data';

import 'encrypted_store.dart';
import 'execution_policy.dart';

class CheckpointRecord {
  CheckpointRecord({
    required this.assignmentId,
    required this.attemptId,
    required this.fenceToken,
    required this.modelVersionId,
    required this.modelDigest,
    required this.inputDigest,
    required this.sequence,
    required this.progressMilli,
    required this.runtimeStateDigest,
    required this.encryptedBlobRef,
    required this.savedAt,
  });

  factory CheckpointRecord.fromJson(Map<String, dynamic> json) => CheckpointRecord(
        assignmentId: json['assignmentId'] as String,
        attemptId: json['attemptId'] as String,
        fenceToken: json['fenceToken'] as int,
        modelVersionId: json['modelVersionId'] as String,
        modelDigest: json['modelDigest'] as String,
        inputDigest: json['inputDigest'] as String,
        sequence: json['sequence'] as int,
        progressMilli: json['progressMilli'] as int,
        runtimeStateDigest: json['runtimeStateDigest'] as String,
        encryptedBlobRef: json['encryptedBlobRef'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );

  final String assignmentId;
  final String attemptId;
  final int fenceToken;
  final String modelVersionId;
  final String modelDigest;
  final String inputDigest;
  final int sequence;
  final int progressMilli;
  final String runtimeStateDigest;
  final String encryptedBlobRef;
  final DateTime savedAt;

  bool get isExpired =>
      DateTime.now().difference(savedAt).inMinutes > ExecutionPolicy.checkpointRetentionMinutes;

  Map<String, dynamic> toJson() => {
        'assignmentId': assignmentId,
        'attemptId': attemptId,
        'fenceToken': fenceToken,
        'modelVersionId': modelVersionId,
        'modelDigest': modelDigest,
        'inputDigest': inputDigest,
        'sequence': sequence,
        'progressMilli': progressMilli,
        'runtimeStateDigest': runtimeStateDigest,
        'encryptedBlobRef': encryptedBlobRef,
        'savedAt': savedAt.toIso8601String(),
      };

  bool canResume({
    required int activeFenceToken,
    required String activeModelDigest,
    required String activeInputDigest,
  }) {
    if (isExpired) {
      return false;
    }
    return fenceToken == activeFenceToken &&
        modelDigest == activeModelDigest &&
        inputDigest == activeInputDigest;
  }
}

class CheckpointStore {
  CheckpointStore(this._store);

  static const _indexKey = 'runtime/checkpoints/index';

  final EncryptedStore _store;

  Future<CheckpointRecord?> latestFor(String assignmentId) async {
    final records = await listAll();
    CheckpointRecord? latest;
    for (final record in records) {
      if (record.assignmentId != assignmentId) {
        continue;
      }
      if (latest == null || record.sequence > latest.sequence) {
        latest = record;
      }
    }
    return latest;
  }

  Future<List<CheckpointRecord>> listAll() async {
    final raw = await _store.read(_indexKey);
    if (raw == null) {
      return [];
    }
    final decoded = jsonDecode(utf8.decode(raw)) as List<dynamic>;
    return decoded.map((item) => CheckpointRecord.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<void> save(CheckpointRecord record, Uint8List encryptedState) async {
    await _store.write(record.encryptedBlobRef, encryptedState);
    final records = await listAll();
    records.removeWhere((item) => item.assignmentId == record.assignmentId);
    records.add(record);
    await _store.write(_indexKey, Uint8List.fromList(utf8.encode(jsonEncode(records.map((e) => e.toJson()).toList()))));
  }

  Future<Uint8List?> readState(CheckpointRecord record) => _store.read(record.encryptedBlobRef);

  Future<void> purge(String assignmentId) async {
    final records = await listAll();
    final remaining = <CheckpointRecord>[];
    for (final record in records) {
      if (record.assignmentId == assignmentId) {
        await _store.delete(record.encryptedBlobRef);
      } else {
        remaining.add(record);
      }
    }
    await _store.write(_indexKey, Uint8List.fromList(utf8.encode(jsonEncode(remaining.map((e) => e.toJson()).toList()))));
  }
}
