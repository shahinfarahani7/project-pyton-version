import 'context_budget_manager.dart';
import 'summarize_constraint_renderer.dart';
import 'summarize_task_constraints.dart';

abstract final class PromptTemplates {
  static const version = '1.0';

  static final int _maxJsonOutputChars =
      (ContextBudgetProfile.qwenBaselineOutputReserveTokens *
              const TokenEstimator().charactersPerToken *
              0.85)
          .floor();

  static String _sizeLimit() =>
      'Keep the whole JSON under $_maxJsonOutputChars characters; '
      'shorten every field as needed to fit.';

  static const _summaryKeys =
      'summary, keyPoints, mainComplaint, suggestedImprovement, '
      'missingOrUnclear';

  static const _summaryShape =
      '{"summary":"...","keyPoints":["..."],"mainComplaint":"...",'
      '"suggestedImprovement":"...","missingOrUnclear":["..."]}';

  static String _summaryKeyGuard() =>
      'Return one JSON object with exactly these five keys and no others: '
      '$_summaryKeys.';

  static String _answerNow(String subject) =>
      'Now write the JSON object about the $subject above. '
      'Use your own short wording, never a sentence copied from it.';

  static String _customerInstructionsBlock(String? userInstructions) {
    if (userInstructions == null || userInstructions.isEmpty) {
      return '';
    }
    return '\nCustomer instructions:\n$userInstructions\n';
  }

  static String documentExtract({
    required String ocrText,
    required double ocrConfidence,
    required String outputSchemaJson,
  }) =>
      '''
You extract structured data from OCR text.
Return exactly one valid JSON object and no markdown or explanation.
Never invent missing values. Use null when a value is absent or uncertain.
Keep Persian names as written.
Normalize numeric separators, but do not change the monetary unit.
Output must match this JSON schema:
$outputSchemaJson

OCR confidence: $ocrConfidence
OCR text:
---
$ocrText
---
/no_think
''';

  static String documentClassify({
    required String ocrText,
    required String allowedLabelsJson,
  }) =>
      '''
Classify the OCR text into exactly one allowed label.
Allowed labels: $allowedLabelsJson
Return only valid JSON in this form:
{"label":"<allowed-label>","confidence":0.0,"evidence":["short evidence"]}
Do not create a new label.

OCR text:
---
$ocrText
---
/no_think
''';

  /// OCR/document path only. Text summarize uses [textSummarize].
  static String documentSummarize({
    required String ocrText,
    String? userInstructions,
    int keyPointCount = 3,
  }) =>
      '''
Summarize the OCR text in the requested language.
${_summaryKeyGuard()}
$_summaryShape
Do not add facts that are not present in the text.
Return exactly $keyPointCount distinct key points.
Identify the main complaint and one practical suggested improvement.
Only list genuinely missing or unclear information; otherwise return [].
Every string field must be a string and every array field must be an array.
${_customerInstructionsBlock(userInstructions)}${_sizeLimit()}

OCR text:
---
$ocrText
---
${_answerNow('text')}
/no_think
''';

  static String textSummarize({
    required String sourceText,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
  }) {
    final constraintBlock = SummarizeConstraintRenderer.promptBlock(constraints);
    final keyPointLine = constraints?.keyPointCount != null
        ? 'Return exactly ${constraints!.keyPointCount} distinct key points.\n'
        : 'Return a few distinct key points from the source.\n';
    return '''
Summarize the customer source text below.
${_summaryKeyGuard()}
$_summaryShape
Do not add facts that are not present in the source.
$keyPointLine
Identify the main complaint and one practical suggested improvement.
List genuinely missing or unresolved details in missingOrUnclear; otherwise return [].
Preserve numbers, dates, and order ids exactly.
Every string field must be a string and every array field must be an array.
$constraintBlock${_customerInstructionsBlock(userInstructions)}${_sizeLimit()}

Source text:
---
$sourceText
---
${_answerNow('source text')}
/no_think
''';
  }

  static String summarizeMapChunk({
    required String chunkText,
    required int chunkIndex,
    required int totalChunks,
    required String chunkId,
    int maxKeyPoints = 3,
  }) =>
      '''
Extract only what this chunk of a longer document states.
${_summaryKeyGuard()}
$_summaryShape
Do not add facts that are not present in this chunk.
Return at most $maxKeyPoints distinct key points from this chunk only.
mainComplaint is the complaint in this chunk or an empty string.
suggestedImprovement is an empty string unless this chunk states a fix.
Include chunk-stated uncertainties in missingOrUnclear (pending, promised, not received yet).
Copy numbers, dates and ids exactly.
Every string value must be a string and every array value must be an array.
${_sizeLimit()}
Chunk metadata: chunkIndex=$chunkIndex totalChunks=$totalChunks chunkId=$chunkId

Chunk text:
---
$chunkText
---
${_answerNow('chunk')}
/no_think
''';

  static String summarizeReduce({
    required String partialSummariesJson,
    required int chunkCount,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
  }) {
    final constraintBlock = SummarizeConstraintRenderer.promptBlock(constraints);
    final keyPointLine = constraints?.keyPointCount != null
        ? 'Return exactly ${constraints!.keyPointCount} distinct key points.\n'
        : 'Merge overlapping key points without losing distinct facts.\n';
    return '''
Combine the partial summaries into one final summary.
${_summaryKeyGuard()}
$_summaryShape
Merge overlapping key points, preserve factual coverage, and do not invent facts.
$keyPointLine
Identify the main complaint and one practical suggested improvement.
Merge missingOrUnclear entries from partials; dedupe similar items.
Every string value must be a string and every array value must be an array.
$constraintBlock${_customerInstructionsBlock(userInstructions)}${_sizeLimit()}
Partial summaries from $chunkCount chunks:
---
$partialSummariesJson
---
${_answerNow('partial summaries')}
/no_think
''';
  }

  static String summaryConstraintRepair({
    required String sourceText,
    required String invalidSummaryJson,
    required String validationIssue,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
  }) {
    final constraintBlock = SummarizeConstraintRenderer.promptBlock(constraints);
    final keyPointCount = constraints?.keyPointCount ?? 3;
    return '''
Rewrite the invalid summary JSON using the source text.
${_summaryKeyGuard()}
{"summary":"...","keyPoints":[${List.filled(keyPointCount, '"..."').join(',')}],"mainComplaint":"...","suggestedImprovement":"...","missingOrUnclear":["..."]}
Fix these validation failures: $validationIssue
$constraintBlock${_customerInstructionsBlock(userInstructions)}${_sizeLimit()}
Invalid JSON:
---
$invalidSummaryJson
---
Source text:
---
$sourceText
---
${_answerNow('source text')}
/no_think
''';
  }

  @Deprecated('Use summaryConstraintRepair')
  static String summaryQualityRepair({
    required String sourceText,
    required String invalidSummaryJson,
    required String qualityIssue,
    String? userInstructions,
    int keyPointCount = 3,
  }) =>
      summaryConstraintRepair(
        sourceText: sourceText,
        invalidSummaryJson: invalidSummaryJson,
        validationIssue: qualityIssue,
        userInstructions: userInstructions,
        constraints: keyPointCount == 3
            ? null
            : SummarizeTaskConstraintsV1(keyPointCount: keyPointCount),
      );

  static String textClassify({
    required String inputText,
    required String allowedLabelsJson,
  }) =>
      '''
Classify the input text into exactly one allowed label.
Allowed labels: $allowedLabelsJson
Return only valid JSON:
{"label":"<allowed-label>","confidence":0.0,"evidence":["short evidence"]}
Do not create a new label.

Input text:
---
$inputText
---
/no_think
''';

  static String? delimitedBody(String prompt) {
    final end = prompt.lastIndexOf('\n---');
    if (end <= 0) {
      return null;
    }
    final opener = prompt.lastIndexOf('---\n', end);
    if (opener < 0) {
      return null;
    }
    return prompt.substring(opener + 4, end).trim();
  }

  static String summarizeLabeledLines({
    required String sourceText,
    int keyPointCount = 3,
  }) =>
      '''
Answer in plain lines. No JSON, no braces, no quotes.
Write exactly these ${keyPointCount + 4} lines and nothing else:
SUMMARY:
${List.generate(keyPointCount, (index) => 'POINT ${index + 1}:').join('\n')}
COMPLAINT:
IMPROVEMENT:
MISSING:
Put your own short wording after each colon, on the same line.
SUMMARY is one sentence. Each POINT is one different fact from the text.
COMPLAINT is the main problem. IMPROVEMENT is one practical action.
MISSING is a detail the text never states, or the word none.
Keep numbers, dates and ids exact and add no other line.

Text:
---
$sourceText
---
Now write the ${keyPointCount + 4} labelled lines about the text above.
/no_think
''';

  static String jsonRepair({required String brokenJson}) =>
      '''
Fix the following broken JSON. Return only one valid JSON object, no markdown.
---
$brokenJson
---
/no_think
''';

  static String jsonCompact({
    required String oversizedJson,
    required int maxOutputTokens,
    int maxArrayItems = 3,
  }) =>
      '''
Compact the following valid JSON to fewer than $maxOutputTokens tokens.
Preserve its schema and essential facts.
Use short strings, at most $maxArrayItems array items, and remove repetition.
Return only one valid JSON object with no markdown.
---
$oversizedJson
---
/no_think
''';

  static String contractedTask({
    required String taskType,
    required String instruction,
    required String inputJson,
    required String outputSchemaJson,
  }) =>
      '''
You are executing EdgeMint task type "$taskType".
$instruction
Return exactly one JSON object and no markdown or explanation.
Every key in this output contract is required:
$outputSchemaJson
Input:
$inputJson
/no_think
''';

  static String visionTask({
    required String taskType,
    required String instruction,
    required String outputSchemaJson,
    required String contextJson,
  }) =>
      '''
Inspect the attached image for EdgeMint task "$taskType".
$instruction
Use visible evidence only. Return exactly one JSON object and no markdown.
Every key in this output contract is required: $outputSchemaJson
Additional context: $contextJson
/no_think
''';
}
