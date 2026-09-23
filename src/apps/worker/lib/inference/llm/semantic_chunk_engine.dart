import '../../runtime/encrypted_store.dart';
import 'context_budget_manager.dart';
import 'summarize_chunk_experiment.dart';

class ProcessedRange {
  const ProcessedRange({required this.startChar, required this.endChar});

  final int startChar;
  final int endChar;

  Map<String, int> toJson() => {'startChar': startChar, 'endChar': endChar};
}

class SemanticChunk {
  const SemanticChunk({
    required this.chunkId,
    required this.chunkIndex,
    required this.inputHash,
    required this.text,
    required this.processedRange,
    required this.estimatedTokens,
    required this.overlapChars,
  });

  final String chunkId;
  final int chunkIndex;
  final String inputHash;
  final String text;
  final ProcessedRange processedRange;
  final int estimatedTokens;
  final int overlapChars;

  Map<String, dynamic> toMapStageMetadata() => {
    'chunkId': chunkId,
    'chunkIndex': chunkIndex,
    'inputHash': inputHash,
    'processedRange': processedRange.toJson(),
    'estimatedTokens': estimatedTokens,
    'overlapChars': overlapChars,
  };
}

class ChunkPlan {
  const ChunkPlan({
    required this.inputHash,
    required this.chunks,
    required this.tokenBudgetPerChunk,
    required this.overlapTokens,
    this.safeTotalSourceBodyTokenBudget,
    this.effectiveTotalSourceBodyTokenBudget,
    this.preOverlapPackTokenBudget,
    this.experimentalSourceChunkTokenCap,
  });

  final String inputHash;
  final List<SemanticChunk> chunks;
  final int tokenBudgetPerChunk;
  final int overlapTokens;
  final int? safeTotalSourceBodyTokenBudget;
  final int? effectiveTotalSourceBodyTokenBudget;
  final int? preOverlapPackTokenBudget;
  final int? experimentalSourceChunkTokenCap;

  int get totalChunks => chunks.length;

  factory ChunkPlan.single({
    required String inputHash,
    required String text,
    required int estimatedTokens,
    required int tokenBudgetPerChunk,
    required int overlapTokens,
    SummarizeChunkExperimentBudget? experimentBudget,
  }) {
    final budgetMeta = experimentBudget;
    return ChunkPlan(
      inputHash: inputHash,
      tokenBudgetPerChunk: tokenBudgetPerChunk,
      overlapTokens: overlapTokens,
      safeTotalSourceBodyTokenBudget: budgetMeta?.safeTotalSourceBodyTokenBudget,
      effectiveTotalSourceBodyTokenBudget:
          budgetMeta?.effectiveTotalSourceBodyTokenBudget,
      preOverlapPackTokenBudget: budgetMeta?.preOverlapPackTokenBudget,
      experimentalSourceChunkTokenCap: budgetMeta?.appliedCap,
      chunks: [
        SemanticChunk(
          chunkId: _chunkId(
            inputHash: inputHash,
            chunkIndex: 0,
            startChar: 0,
            endChar: text.length,
            text: text,
          ),
          chunkIndex: 0,
          inputHash: inputHash,
          text: text,
          processedRange: ProcessedRange(startChar: 0, endChar: text.length),
          estimatedTokens: estimatedTokens,
          overlapChars: 0,
        ),
      ],
    );
  }
}

class _SemanticSegment {
  const _SemanticSegment({
    required this.text,
    required this.startChar,
    required this.endChar,
  });

  final String text;
  final int startChar;
  final int endChar;
}

/// Deterministic semantic chunker (Architecture Section 27).
class SemanticChunkEngine {
  const SemanticChunkEngine({
    this.profile = ContextBudgetProfile.qwenBaseline,
    this.estimator = const TokenEstimator(),
    this.overlapTokens = 40,
  });

  final ContextBudgetProfile profile;
  final TokenEstimator estimator;
  final int overlapTokens;

  // Leave room for the map-stage instruction and metadata wrapped around
  // every chunk; otherwise a maximal chunk immediately exceeds the same
  // direct-inference budget when its prompt is constructed.
  int get tokenBudgetPerChunk => chunkTokenBudget();

  /// [reservedPromptTokens] must cover every token the caller wraps around a
  /// chunk body: system instruction, template text and customer instructions.
  /// Without a measured reserve the engine falls back to a static estimate of
  /// the template overhead.
  int chunkTokenBudget({int? reservedPromptTokens}) {
    final overhead =
        reservedPromptTokens ??
        (profile.systemTemplateTokens * 2) + profile.safetyMarginTokens;
    return (profile.inputBudgetTokens - overhead - profile.safetyMarginTokens)
        .clamp(1, profile.inputBudgetTokens)
        .toInt();
  }

  ChunkPlan chunk(
    String input, {
    int? reservedPromptTokens,
    int? experimentalSourceChunkTokenCap,
  }) {
    final budget = chunkTokenBudget(reservedPromptTokens: reservedPromptTokens);
    final experimentBudget = _resolveExperimentBudget(
      chunkTokenBudget: budget,
      experimentalSourceChunkTokenCap: experimentalSourceChunkTokenCap,
    );
    final packBudget = experimentBudget.preOverlapPackTokenBudget;
    final effectiveTotalBodyBudget =
        experimentBudget.effectiveTotalSourceBodyTokenBudget;
    final normalized = input.replaceAll('\r\n', '\n');
    final inputHash = sha256HexString(normalized);
    if (normalized.trim().isEmpty) {
      return ChunkPlan.single(
        inputHash: inputHash,
        text: '',
        estimatedTokens: 0,
        tokenBudgetPerChunk: budget,
        overlapTokens: overlapTokens,
        experimentBudget: experimentBudget,
      );
    }

    final estimatedTokens = estimator.estimate(normalized);
    final forceMultiChunk =
        experimentBudget.active &&
        estimatedTokens > effectiveTotalBodyBudget;
    if (!forceMultiChunk && estimatedTokens <= budget) {
      return ChunkPlan.single(
        inputHash: inputHash,
        text: normalized,
        estimatedTokens: estimatedTokens,
        tokenBudgetPerChunk: budget,
        overlapTokens: overlapTokens,
        experimentBudget: experimentBudget,
      );
    }

    final segments = _semanticSegments(normalized);
    // Overlap is merged after packing; reserve [overlapTokens] inside the
    // effective total Map body budget before packing new source content.
    final packed = _packSegments(
      segments,
      maxTokens: packBudget,
    );
    final chunks = _applyOverlap(
      inputHash: inputHash,
      packed: packed,
      source: normalized,
    );
    if (experimentBudget.active) {
      _assertExperimentChunkBodiesWithinBudget(
        chunks: chunks,
        maxTotalBodyTokens: effectiveTotalBodyBudget,
      );
    }

    return ChunkPlan(
      inputHash: inputHash,
      chunks: chunks,
      tokenBudgetPerChunk: budget,
      overlapTokens: overlapTokens,
      safeTotalSourceBodyTokenBudget:
          experimentBudget.safeTotalSourceBodyTokenBudget,
      effectiveTotalSourceBodyTokenBudget: effectiveTotalBodyBudget,
      preOverlapPackTokenBudget: packBudget,
      experimentalSourceChunkTokenCap: experimentBudget.appliedCap,
    );
  }

  void _assertExperimentChunkBodiesWithinBudget({
    required List<SemanticChunk> chunks,
    required int maxTotalBodyTokens,
  }) {
    for (final chunk in chunks) {
      final estimated = estimator.estimate(chunk.text);
      if (estimated > maxTotalBodyTokens) {
        throw StateError(
          'Experiment chunk ${chunk.chunkIndex} body estimate=$estimated '
          'exceeds effectiveTotalBodyTokens=$maxTotalBodyTokens',
        );
      }
    }
  }

  SummarizeChunkExperimentBudget _resolveExperimentBudget({
    required int chunkTokenBudget,
    int? experimentalSourceChunkTokenCap,
  }) =>
      SummarizeChunkExperiment.resolveBudgetFromCap(
        chunkTokenBudget: chunkTokenBudget,
        overlapTokens: overlapTokens,
        requestedCap: experimentalSourceChunkTokenCap,
      );

  List<_SemanticSegment> _semanticSegments(String input) {
    final segments = <_SemanticSegment>[];
    final paragraphPattern = RegExp(r'\n\s*\n');
    var searchStart = 0;

    for (final match in paragraphPattern.allMatches(input)) {
      _appendParagraphSegments(
        input.substring(searchStart, match.start),
        offset: searchStart,
        sink: segments,
      );
      searchStart = match.end;
    }
    _appendParagraphSegments(
      input.substring(searchStart),
      offset: searchStart,
      sink: segments,
    );

    if (segments.isEmpty) {
      segments.add(
        _SemanticSegment(
          text: input.trim(),
          startChar: 0,
          endChar: input.length,
        ),
      );
    }
    return segments;
  }

  void _appendParagraphSegments(
    String paragraph, {
    required int offset,
    required List<_SemanticSegment> sink,
  }) {
    final trimmed = paragraph.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final localStart = paragraph.indexOf(trimmed);
    final base = offset + localStart;
    final sentencePattern = RegExp(r'[^.!?]+[.!?]+');

    for (final match in sentencePattern.allMatches(trimmed)) {
      final sentence = trimmed.substring(match.start, match.end).trim();
      if (sentence.isEmpty) {
        continue;
      }
      sink.add(
        _SemanticSegment(
          text: sentence,
          startChar: base + match.start,
          endChar: base + match.end,
        ),
      );
    }
  }

  /// A single sentence (or a run of text without sentence punctuation) can be
  /// larger than a whole chunk, so it is split on word boundaries before
  /// packing. Without this a maximal segment would travel to the runtime as
  /// one oversized prompt.
  List<_SemanticSegment> _fitSegments(
    List<_SemanticSegment> segments, {
    required int maxTokens,
  }) {
    final maxChars = (maxTokens * estimator.charactersPerToken).floor().clamp(
      1,
      1 << 30,
    );
    final fitted = <_SemanticSegment>[];

    for (final segment in segments) {
      if (segment.text.length <= maxChars) {
        fitted.add(segment);
        continue;
      }

      var offset = 0;
      while (offset < segment.text.length) {
        var end = offset + maxChars;
        if (end >= segment.text.length) {
          end = segment.text.length;
        } else {
          final boundary = segment.text.lastIndexOf(' ', end);
          if (boundary > offset) {
            end = boundary;
          }
        }
        final piece = segment.text.substring(offset, end);
        if (piece.trim().isNotEmpty) {
          fitted.add(
            _SemanticSegment(
              text: piece.trim(),
              startChar: segment.startChar + offset,
              endChar: segment.startChar + end,
            ),
          );
        }
        offset = end < segment.text.length && segment.text[end] == ' '
            ? end + 1
            : end;
      }
    }

    return fitted;
  }

  List<List<_SemanticSegment>> _packSegments(
    List<_SemanticSegment> segments, {
    required int maxTokens,
  }) {
    final packed = <List<_SemanticSegment>>[];
    var current = <_SemanticSegment>[];
    var currentTokens = 0;

    for (final segment in _fitSegments(segments, maxTokens: maxTokens)) {
      final segmentTokens = estimator.estimate(segment.text);
      final separatorTokens = current.isEmpty ? 0 : 1;
      if (current.isNotEmpty &&
          currentTokens + separatorTokens + segmentTokens > maxTokens) {
        packed.add(current);
        current = <_SemanticSegment>[];
        currentTokens = 0;
      }
      current.add(segment);
      currentTokens += (current.length == 1 ? 0 : 1) + segmentTokens;
    }

    if (current.isNotEmpty) {
      packed.add(current);
    }
    return packed;
  }

  List<SemanticChunk> _applyOverlap({
    required String inputHash,
    required List<List<_SemanticSegment>> packed,
    required String source,
  }) {
    final chunks = <SemanticChunk>[];
    String? previousTail;

    for (var index = 0; index < packed.length; index++) {
      final group = packed[index];
      final body = group.map((segment) => segment.text).join(' ');
      final startChar = group.first.startChar;
      final endChar = group.last.endChar;

      var overlapChars = 0;
      var text = body;
      if (index > 0 && previousTail != null && previousTail.isNotEmpty) {
        overlapChars = previousTail.length;
        text = _mergeOverlap(previousTail, body);
      }

      chunks.add(
        SemanticChunk(
          chunkId: _chunkId(
            inputHash: inputHash,
            chunkIndex: index,
            startChar: startChar,
            endChar: endChar,
            text: text,
          ),
          chunkIndex: index,
          inputHash: inputHash,
          text: text,
          processedRange: ProcessedRange(
            startChar: startChar,
            endChar: endChar,
          ),
          estimatedTokens: estimator.estimate(text),
          overlapChars: overlapChars,
        ),
      );

      previousTail = _overlapTail(source, endChar: endChar);
    }

    return chunks;
  }

  String _overlapTail(String source, {required int endChar}) {
    if (overlapTokens <= 0) {
      return '';
    }
    final maxChars = (overlapTokens * 3.5).ceil();
    final sliceStart = (endChar - maxChars).clamp(0, source.length);
    var tail = source.substring(sliceStart, endChar).trimLeft();

    final sentenceStart = tail.indexOf(RegExp(r'[A-Za-z0-9]'));
    if (sentenceStart > 0) {
      tail = tail.substring(sentenceStart);
    }
    return tail;
  }

  String _mergeOverlap(String overlap, String body) {
    if (body.startsWith(overlap)) {
      return body;
    }
    final maxCheck = overlap.length.clamp(0, body.length);
    for (var size = maxCheck; size > 0; size--) {
      final suffix = overlap.substring(overlap.length - size);
      if (body.startsWith(suffix)) {
        return '$overlap${body.substring(size)}';
      }
    }
    return '$overlap $body';
  }
}

String _chunkId({
  required String inputHash,
  required int chunkIndex,
  required int startChar,
  required int endChar,
  required String text,
}) {
  return sha256HexString(
    '$inputHash:$chunkIndex:$startChar:$endChar:${text.length}',
  );
}
