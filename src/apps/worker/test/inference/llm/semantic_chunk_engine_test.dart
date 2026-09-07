import 'package:edgemint_worker/inference/llm/semantic_chunk_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/semantic_chunk_golden.dart';

void main() {
  group('SemanticChunkEngine', () {
    const engine = SemanticChunkEngine();

    test('short input stays a single chunk', () {
      const input = 'One short paragraph. Two sentences only.';
      final first = engine.chunk(input);
      final second = engine.chunk(input);

      expect(first.totalChunks, 1);
      expect(second.totalChunks, 1);
      expect(first.chunks.single.text, input);
      expect(first.chunks.single.chunkId, second.chunks.single.chunkId);
    });

    test('golden fixture produces deterministic chunk boundaries and metadata', () {
      final input = semanticChunkGoldenInput();
      final first = engine.chunk(input);
      final second = engine.chunk(input);

      expect(first.totalChunks, greaterThanOrEqualTo(semanticChunkGoldenExpected['minChunks'] as int));
      expect(first.chunks.first.chunkIndex, semanticChunkGoldenExpected['firstChunkIndex']);
      expect(first.inputHash, second.inputHash);
      expect(first.chunks.length, second.chunks.length);

      for (var i = 0; i < first.chunks.length; i++) {
        final chunk = first.chunks[i];
        final replay = second.chunks[i];

        expect(chunk.chunkIndex, i);
        expect(chunk.chunkId, replay.chunkId);
        expect(chunk.chunkId.length, semanticChunkGoldenFirstChunkIdPrefixLength);
        expect(chunk.inputHash, first.inputHash);
        expect(chunk.estimatedTokens, lessThanOrEqualTo(engine.tokenBudgetPerChunk + engine.overlapTokens));
        expect(chunk.text.trim(), isNotEmpty);
        expect(chunk.processedRange.startChar, lessThan(chunk.processedRange.endChar));
        expect(chunk.toMapStageMetadata()['chunkIndex'], i);
      }

      if (first.totalChunks > 1) {
        expect(first.chunks[1].overlapChars, greaterThan(0));
      }
    });

    test('chunk ids change when input changes', () {
      final baseline = engine.chunk(semanticChunkGoldenInput());
      final mutated = engine.chunk('${semanticChunkGoldenInput()} Extra sentence.');
      expect(mutated.inputHash, isNot(equals(baseline.inputHash)));
      expect(mutated.chunks.first.chunkId, isNot(equals(baseline.chunks.first.chunkId)));
    });
  });
}
