import 'dart:convert';
import 'dart:typed_data';

import 'resume_grant.dart';
import '../inference/llm/prompt_templates.dart';
import '../inference/llm/semantic_chunk_engine.dart';
import '../models/worker_model_catalog.dart';
import 'encrypted_store.dart';
import 'execution_policy.dart';
import 'runtime_exceptions.dart';

/// Chunk checkpoint metadata (Architecture Section 28).
class ChunkCheckpointRecord {
  ChunkCheckpointRecord({
    required this.assignmentId,
    required this.fenceToken,
    required this.chunkIndex,
    required this.chunkId,
    required this.inputHash,
    required this.summaryHash,
    required this.modelVersionId,
    required this.runtimeVersion,
    required this.promptVersion,
    required this.processedRange,
    required this.partialSummary,
    required this.savedAt,
  });

  factory ChunkCheckpointRecord.fromJson(Map<String, dynamic> json) => ChunkCheckpointRecord(
        assignmentId: json['assignmentId'] as String,
        fenceToken: json['fenceToken'] as int,
        chunkIndex: json['chunkIndex'] as int,
        chunkId: json['chunkId'] as String,
        inputHash: json['inputHash'] as String,
        summaryHash: json['summaryHash'] as String,
        modelVersionId: json['modelVersionId'] as String,
        runtimeVersion: json['runtimeVersion'] as String,
        promptVersion: json['promptVersion'] as String,
        processedRange: ProcessedRange(
          startChar: json['processedRange']['startChar'] as int,
          endChar: json['processedRange']['endChar'] as int,
        ),
        partialSummary: Map<String, dynamic>.from(json['partialSummary'] as Map),
        savedAt: DateTime.parse(json['savedAt'] as String),
      );

  final String assignmentId;
  final int fenceToken;
  final int chunkIndex;
  final String chunkId;
  final String inputHash;
  final String summaryHash;
  final String modelVersionId;
  final String runtimeVersion;
  final String promptVersion;
  final ProcessedRange processedRange;
  final Map<String, dynamic> partialSummary;
  final DateTime savedAt;

  bool get isExpired =>
      DateTime.now().difference(savedAt).inMinutes > ExecutionPolicy.checkpointRetentionMinutes;

  Map<String, dynamic> toJson() => {
        'assignmentId': assignmentId,
        'fenceToken': fenceToken,
        'chunkIndex': chunkIndex,
        'chunkId': chunkId,
        'inputHash': inputHash,
        'summaryHash': summaryHash,
        'modelVersionId': modelVersionId,
        'runtimeVersion': runtimeVersion,
        'promptVersion': promptVersion,
        'processedRange': processedRange.toJson(),
        'partialSummary': partialSummary,
        'savedAt': savedAt.toIso8601String(),
      };

  bool canResume({
    required int activeFenceToken,
    required String activeInputHash,
    required String activeModelVersionId,
    required String activePromptVersion,
    required String activeRuntimeVersion,
  }) {
    if (isExpired) {
      return false;
    }
    return fenceToken == activeFenceToken &&
        inputHash == activeInputHash &&
        modelVersionId == activeModelVersionId &&
        promptVersion == activePromptVersion &&
        runtimeVersion == activeRuntimeVersion;
  }
}

class ChunkCheckpointResumeState {
  const ChunkCheckpointResumeState({
    required this.completedPartials,
    required this.nextChunkIndex,
    required this.inputHash,
    required this.fenceToken,
  });

  final List<Map<String, dynamic>> completedPartials;
  final int nextChunkIndex;
  final String inputHash;
  final int fenceToken;
}

/// Fence-aware chunk checkpoint coordinator for map/reduce resume.
class CheckpointManager {
  CheckpointManager(this._store);

  static const runtimeVersion = 'flutter_gemma_mediapipe_v1';
  static const _indexKey = 'runtime/chunk_checkpoints/index';

  final EncryptedStore _store;

  Future<ChunkCheckpointRecord> saveChunkCheckpoint({
    required String assignmentId,
    required int fenceToken,
    required SemanticChunk chunk,
    required Map<String, dynamic> partialSummary,
    String modelVersionId = WorkerModelCatalog.modelVersionId,
    String? promptVersion,
    String runtimeVersion = CheckpointManager.runtimeVersion,
  }) async {
    final activePromptVersion = promptVersion ?? PromptTemplates.version;
    final summaryHash = sha256HexString(jsonEncode(partialSummary));
    final record = ChunkCheckpointRecord(
      assignmentId: assignmentId,
      fenceToken: fenceToken,
      chunkIndex: chunk.chunkIndex,
      chunkId: chunk.chunkId,
      inputHash: chunk.inputHash,
      summaryHash: summaryHash,
      modelVersionId: modelVersionId,
      runtimeVersion: runtimeVersion,
      promptVersion: activePromptVersion,
      processedRange: chunk.processedRange,
      partialSummary: partialSummary,
      savedAt: DateTime.now().toUtc(),
    );
    final records = await _listAll();
    records.removeWhere(
      (item) => item.assignmentId == assignmentId && item.chunkIndex == chunk.chunkIndex,
    );
    records.add(record);
    await _writeIndex(records);
    return record;
  }

  Future<ChunkCheckpointResumeState?> loadResumableState({
    required String assignmentId,
    required int activeFenceToken,
    required String inputHash,
    String modelVersionId = WorkerModelCatalog.modelVersionId,
    String? promptVersion,
    String runtimeVersion = CheckpointManager.runtimeVersion,
    ResumeGrant? resumeGrant,
  }) async {
    final activePromptVersion = promptVersion ?? PromptTemplates.version;
    final records = (await _listAll())
        .where((record) => record.assignmentId == assignmentId ||
            (resumeGrant != null &&
                record.assignmentId == resumeGrant.producerAssignmentId))
        .toList()
      ..sort((left, right) => left.chunkIndex.compareTo(right.chunkIndex));

    if (records.isEmpty) {
      return null;
    }

    if (resumeGrant != null) {
      final compatibility = ResumeGrantValidator.evaluate(
        grant: resumeGrant,
        assignmentId: assignmentId,
        activeFenceToken: activeFenceToken,
        inputDigest: inputHash,
        modelVersionId: modelVersionId,
        runtimeVersion: runtimeVersion,
        promptTemplateVersion: activePromptVersion,
        executionPlanVersion: '2026-q3-v1',
        requestedChunkIds: records.map((record) => record.chunkId),
      );
      if (!compatibility.permitted) {
        throw ResumeGrantRejectedException(compatibility);
      }
    }

    final valid = <ChunkCheckpointRecord>[];
    for (final record in records) {
      final sameAssignmentResume = resumeGrant == null &&
          record.canResume(
            activeFenceToken: activeFenceToken,
            activeInputHash: inputHash,
            activeModelVersionId: modelVersionId,
            activePromptVersion: activePromptVersion,
            activeRuntimeVersion: runtimeVersion,
          );
      final grantResume = resumeGrant != null &&
          record.inputHash == inputHash &&
          record.modelVersionId == modelVersionId &&
          record.promptVersion == activePromptVersion &&
          record.runtimeVersion == runtimeVersion &&
          record.fenceToken == resumeGrant.producerFenceToken &&
          resumeGrant.authorizedChunkIds.contains(record.chunkId) &&
          !record.isExpired;
      if (!sameAssignmentResume && !grantResume) {
        await purge(assignmentId);
        if (resumeGrant?.producerAssignmentId == record.assignmentId) {
          await purge(resumeGrant!.producerAssignmentId);
        }
        return null;
      }
      if (valid.isNotEmpty && record.chunkIndex != valid.last.chunkIndex + 1) {
        await purge(assignmentId);
        return null;
      }
      valid.add(record);
    }

    return ChunkCheckpointResumeState(
      completedPartials: valid.map((record) => record.partialSummary).toList(growable: false),
      nextChunkIndex: valid.length,
      inputHash: inputHash,
      fenceToken: activeFenceToken,
    );
  }

  void assertFenceOnResume({
    required int activeFenceToken,
    required ChunkCheckpointResumeState state,
  }) {
    if (state.fenceToken != activeFenceToken) {
      throw StaleFenceException(activeFenceToken, state.fenceToken);
    }
  }

  Future<void> purge(String assignmentId) async {
    final remaining = (await _listAll()).where((record) => record.assignmentId != assignmentId).toList();
    await _writeIndex(remaining);
  }

  Future<List<ChunkCheckpointRecord>> _listAll() async {
    final raw = await _store.read(_indexKey);
    if (raw == null) {
      return [];
    }
    final decoded = jsonDecode(utf8.decode(raw)) as List<dynamic>;
    return decoded
        .map((item) => ChunkCheckpointRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _writeIndex(List<ChunkCheckpointRecord> records) async {
    await _store.write(
      _indexKey,
      Uint8List.fromList(utf8.encode(jsonEncode(records.map((record) => record.toJson()).toList()))),
    );
  }
}
