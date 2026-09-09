import 'package:flutter_test/flutter_test.dart';

/// Deterministic long-form input guaranteed to exceed the Qwen baseline
/// input token budget, forcing [SemanticChunkEngine] to split it into
/// multiple chunks. Used by checkpoint/resume tests that need a plan with
/// `totalChunks > 1`.
///
/// Built from repeated, varied paragraphs (not a single repeated sentence)
/// so the semantic/sentence-boundary chunker has realistic paragraph and
/// sentence breaks to split on.
String semanticChunkGoldenInput() {
  final paragraphs = List<String>.generate(40, (i) {
    return 'Section $i of the EdgeMint worker readiness report. '
        'This paragraph describes deterministic checkpoint behavior for '
        'chunk index $i during a simulated hierarchical summarize task. '
        'It intentionally repeats structural language so the token '
        'estimator produces a stable, predictable chunk count across '
        'test runs. The device must remain within thermal and storage '
        'budgets while processing this section, and the fence token must '
        'be validated before any partial summary for this section is '
        'reused after a resume.';
  });
  return paragraphs.join('\n\n');
}

/// Lightweight assumption helper for tests.
///
/// Unlike [expect], a failed assumption is reported as a normal test
/// failure (so CI still catches a regression that shrinks the golden
/// input below the multi-chunk threshold), but the intent is documented
/// as a precondition on the fixture data rather than the behavior under
/// test.
void assumeTrue(bool condition, [String? reason]) {
  expect(
    condition,
    isTrue,
    reason: reason ?? 'expected precondition on fixture data to hold',
  );
}