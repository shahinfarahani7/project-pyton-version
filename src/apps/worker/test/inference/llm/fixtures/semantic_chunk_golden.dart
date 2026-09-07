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

/// Expected stable metadata for [semanticChunkGoldenInput].
const semanticChunkGoldenExpected = {
  'minChunks': 2,
  'firstChunkIndex': 0,
  'requiresOverlapOnSecondChunk': true,
};

/// Known chunk id prefix snapshot for regression (full id is sha256 hex).
const semanticChunkGoldenFirstChunkIdPrefixLength = 64;
