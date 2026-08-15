abstract final class PromptTemplates {
  static const version = '1.0';

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

  static String documentSummarize({required String ocrText}) =>
      '''
Summarize the OCR text in the requested language.
Return only valid JSON:
{"summary":"...","keyPoints":["..."],"missingOrUnclear":["..."]}
Do not add facts that are not present in the text.
Keep the summary short.

OCR text:
---
$ocrText
---
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

  static String jsonRepair({required String brokenJson}) =>
      '''
Fix the following broken JSON. Return only one valid JSON object, no markdown.
---
$brokenJson
---
/no_think
''';
}
