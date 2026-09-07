/// Builds the exact formatted prompt counted before native inference (v2 §25.1).
abstract final class FormattedPromptBuilder {
  static const noThinkSuffix = '/no_think';
  static const separator = '---';

  static String buildTaskPrompt({
    required String templateBody,
    String? systemInstruction,
  }) {
    final system = (systemInstruction ?? '').trim();
    if (system.isEmpty) {
      return '$templateBody\n$noThinkSuffix';
    }
    return '$system\n\n$templateBody\n$noThinkSuffix';
  }

  static String buildContractedTask({
    required String taskType,
    required String instruction,
    required String inputJson,
    required String outputSchemaJson,
    String? systemInstruction,
  }) {
    return buildTaskPrompt(
      systemInstruction: systemInstruction,
      templateBody: '''
You are executing EdgeMint task type "$taskType".
$instruction
Return exactly one JSON object and no markdown or explanation.
Every key in this output contract is required:
$outputSchemaJson
Input:
$inputJson
''',
    );
  }
}
