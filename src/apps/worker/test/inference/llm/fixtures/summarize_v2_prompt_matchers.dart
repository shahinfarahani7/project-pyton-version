/// Shared prompt fragments for mocks and contract tests under [SummarizeEvidencePipeline].
library;

bool isEvidenceV2FinalReducePrompt(String prompt) =>
    prompt.contains('Produce the final customer-facing summary from merged evidence');

bool isLegacyFinalReducePrompt(String prompt) =>
    prompt.contains('Combine the partial summaries into one final summary');

bool isFinalReducePrompt(String prompt) =>
    isLegacyFinalReducePrompt(prompt) || isEvidenceV2FinalReducePrompt(prompt);

bool isEvidenceV2IntermediateReducePrompt(String prompt) =>
    prompt.contains('Merge these evidence partials into one intermediate evidence');

bool isLegacyIntermediateReducePrompt(String prompt) =>
    prompt.contains('merged intermediate summary');

bool isIntermediateReducePrompt(String prompt) =>
    isLegacyIntermediateReducePrompt(prompt) ||
    isEvidenceV2IntermediateReducePrompt(prompt);

bool isEvidenceV2MapChunkPrompt(String prompt) =>
    prompt.contains('Return one JSON object with exactly these four keys');

/// Prompt line break splits "15–25" from "words" in map evidence guidance.
const evidenceMapFactLengthGuidance = '15–25';
