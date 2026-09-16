import 'package:edgemint_worker/inference/llm/semantic_chunk_engine.dart';

/// Golden input for deterministic semantic chunk boundaries.
///
/// Three paragraphs with multiple sentences; exceeds the 600-token input budget.
String semanticChunkGoldenInput() {
  final paragraphOne = List.filled(
    8,
    'Alpha paragraph sentence keeps semantic boundaries intact.',
  ).join(' ');
  final paragraphTwo = List.filled(
    10,
    'Beta paragraph continues with stable punctuation! Does overlap work? Yes.',
  ).join(' ');
  final paragraphThree = List.filled(
    12,
    'Gamma paragraph extends the document for map-stage metadata coverage.',
  ).join(' ');
  return '$paragraphOne\n\n$paragraphTwo\n\n$paragraphThree';
}

/// Golden input repeated until it is larger than one chunk budget, so the
/// boundary regression keeps exercising the multi-chunk path.
String semanticChunkGoldenMultiChunkInput({
  SemanticChunkEngine engine = const SemanticChunkEngine(),
}) {
  final unit = semanticChunkGoldenInput();
  final unitTokens = engine.estimator.estimate(unit);
  final repeats = (engine.tokenBudgetPerChunk * 2 / unitTokens).ceil().clamp(
    2,
    32,
  );
  return List<String>.filled(repeats, unit).join('\n\n');
}

/// Expected stable metadata for [semanticChunkGoldenInput].
const semanticChunkGoldenExpected = {
  'minChunks': 2,
  'firstChunkIndex': 0,
  'requiresOverlapOnSecondChunk': true,
};

/// Known chunk id prefix snapshot for regression (full id is sha256 hex).
const semanticChunkGoldenFirstChunkIdPrefixLength = 64;
