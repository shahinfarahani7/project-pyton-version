import 'context_budget_manager.dart';

abstract final class PromptTemplates {
  static const version = '1.0';

  /// The MediaPipe `.task` path ignores `maxOutputTokens`, so the output
  /// reserve has to be stated in the prompt as well as stopped at the runtime.
  /// A reply longer than this is cut mid-string and has to be salvaged.
  static final int _maxJsonOutputChars =
      (ContextBudgetProfile.qwenBaselineOutputReserveTokens *
              const TokenEstimator().charactersPerToken *
              0.85)
          .floor();

  static String _sizeLimit() =>
      'Keep the whole JSON under $_maxJsonOutputChars characters; '
      'shorten every field as needed to fit.';

  /// Summarize field names, named once so the prompts can forbid every other
  /// key explicitly.
  static const _summaryKeys =
      'summary, keyPoints, mainComplaint, suggestedImprovement, '
      'missingOrUnclear';

  static const _summaryShape =
      '{"summary":"...","keyPoints":["..."],"mainComplaint":"...",'
      '"suggestedImprovement":"...","missingOrUnclear":["..."]}';

  /// Map stage never reports missing information, so its shape shows the empty
  /// array the rules ask for. A placeholder the rules contradict is one more
  /// thing for the model to copy.
  static const _summaryMapShape =
      '{"summary":"...","keyPoints":["..."],"mainComplaint":"...",'
      '"suggestedImprovement":"...","missingOrUnclear":[]}';

  /// Rules are written as sentences rather than `- name: value` lines. A 0.5B
  /// model copies anything shaped like a field spec into its answer, which is
  /// how `"KeepNumbersDatesIdsExact":true` and an unquoted `DoNotInventFacts`
  /// key ended up in a summarize reply. Every extra line here shrinks the
  /// chunk budget, so the guard stays a single sentence.
  static String _summaryKeyGuard() =>
      'Return one JSON object with exactly these five keys and no others: '
      '$_summaryKeys.';

  /// Repeated after the source text. A 0.5B model follows whichever
  /// instruction sits closest to where it starts writing; with the rules only
  /// at the top it continues the text instead and copies it verbatim into
  /// `summary` until the output budget runs out.
  static String _answerNow(String subject) =>
      'Now write the JSON object about the $subject above. '
      'Use your own short wording, never a sentence copied from it.';

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
The summary must contain at most 2 concise sentences.
Return exactly $keyPointCount distinct key points, each at most 12 words.
Identify the main complaint and one practical suggested improvement.
Only list genuinely missing or unclear information; otherwise return [].
Never copy a whole sentence from the source or repeat a fact across fields.
Every string field must be a string and every array field must be an array.
${userInstructions == null || userInstructions.trim().isEmpty ? '' : '\nCustomer instructions:\n${userInstructions.trim()}\n'}
${_sizeLimit()}

OCR text:
---
$ocrText
---
${_answerNow('text')}
/no_think
''';

  /// Map stage only extracts what its own chunk states. The customer's output
  /// requirements (key point count, topic coverage) belong to the reduce stage:
  /// asking one chunk to cover topics it does not contain is what makes a small
  /// model pad the answer with repeated sentences.
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
$_summaryMapShape
summary is at most 2 short sentences.
keyPoints holds at most $maxKeyPoints distinct facts of 12 words each, never the same fact twice.
mainComplaint is the complaint in this chunk or an empty string.
suggestedImprovement is an empty string unless this chunk states a fix.
missingOrUnclear is always an empty array.
Copy numbers, dates and ids exactly. Never copy a whole sentence from the chunk.
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
    int keyPointCount = 3,
  }) =>
      '''
Combine the partial summaries into one final summary.
${_summaryKeyGuard()}
$_summaryShape
Merge overlapping key points, preserve factual coverage, and do not invent facts.
Use at most 2 concise summary sentences and exactly $keyPointCount distinct short key points.
Identify the main complaint and one practical suggested improvement.
Return [] for missingOrUnclear unless information is genuinely unclear.
Every string value must be a string and every array value must be an array.
${userInstructions == null || userInstructions.trim().isEmpty ? '' : '\nCustomer instructions:\n${userInstructions.trim()}\n'}
${_sizeLimit()}
Partial summaries from $chunkCount chunks:
---
$partialSummariesJson
---
${_answerNow('partial summaries')}
/no_think
''';

  static String summaryQualityRepair({
    required String sourceText,
    required String invalidSummaryJson,
    required String qualityIssue,
    String? userInstructions,
    int keyPointCount = 3,
  }) =>
      '''
Rewrite the invalid summary JSON using the source text.
${_summaryKeyGuard()}
{"summary":"...","keyPoints":[${List.filled(keyPointCount, '"..."').join(',')}],"mainComplaint":"...","suggestedImprovement":"...","missingOrUnclear":[]}
keyPoints must contain exactly $keyPointCount distinct facts from the source.
mainComplaint must identify the central complaint.
suggestedImprovement must be one practical action based on the complaint.
Never copy a whole sentence from the source or repeat a sentence across fields.
The previous response failed because: $qualityIssue
${userInstructions == null || userInstructions.trim().isEmpty ? '' : '\nCustomer instructions:\n${userInstructions.trim()}\n'}
${_sizeLimit()}
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

  /// The content a task template wraps between the last pair of `---` fences,
  /// so a failed call can be re-asked for the same content in another output
  /// format without the caller threading the text through again.
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

  /// Used when a summarize reply cannot be parsed as JSON even after the
  /// deterministic repairs. Labelled lines have no syntax to break, and the
  /// caller rebuilds the JSON itself.
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
