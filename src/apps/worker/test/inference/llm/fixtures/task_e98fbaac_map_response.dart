/// Map-stage model output for task `tsk_dev_e98fbaac` (log 20260921-084119).
///
/// Extracted from the full [INFERENCE RESPONSE map] block and cross-checked against
/// [MODEL RESPONSE] in the same run. Log prefixes removed; string escapes preserved.
///
/// Log metadata: chars=687, utf8Bytes=687,
/// sha256=bf6e1f2e9ec47b2175a5df04ebde2a93423272fd1b745d28675a543a4a634e51,
/// stopReason=json_complete, truncated=false.
const taskE98fbaacLogChars = 687;
const taskE98fbaacLogUtf8Bytes = 687;
const taskE98fbaacLogSha256 =
    'bf6e1f2e9ec47b2175a5df04ebde2a93423272fd1b745d28675a543a4a634e51';

/// JSON core from the log (opening ` ```json ` fence, no decorative closing fence).
const taskE98fbaacMapResponseCore =
    '```json\n{\n'
    '  "summary": "A customer reports a delayed delivery and an incorrect substitution in their grocery order.",\n'
    '  "keyPoints": ["Delayed delivery of order B410 by 40 minutes.", "Incorrect substitution of regular milk in order B426.", "Pending refund for incorrect milk in B426.", "Uncertainty about the substitution approval process in B426."],\n'
    '  "mainComplaint": "Delayed delivery and incorrect substitution in grocery orders.",\n'
    '  "suggestedImprovement": "Provide clear and accurate delivery estimates and support for substitution decisions.",\n'
    '  "missingOrUnclear": ["Pending refund for incorrect milk in B426.", "Uncertainty about the substitution approval process in B426."]\n'
    '}';

/// Full device buffer length (687): core JSON plus malformed closing `` ` `` line
/// left when generation stopped at `json_complete`.
const taskE98fbaacMapResponseRaw = '$taskE98fbaacMapResponseCore\n`';

/// Same JSON payload when the model places `{` on the opening fence line
/// (` ```json {` instead of ` ```json` + newline + `{`). Reproduces the live
/// `json_extract_no_object` failure mode against the pre-fix fence stripper.
const taskE98fbaacMapResponseBraceOnFenceLine =
    '```json {\n'
    '  "summary": "A customer reports a delayed delivery and an incorrect substitution in their grocery order.",\n'
    '  "keyPoints": ["Delayed delivery of order B410 by 40 minutes.", "Incorrect substitution of regular milk in order B426.", "Pending refund for incorrect milk in B426.", "Uncertainty about the substitution approval process in B426."],\n'
    '  "mainComplaint": "Delayed delivery and incorrect substitution in grocery orders.",\n'
    '  "suggestedImprovement": "Provide clear and accurate delivery estimates and support for substitution decisions.",\n'
    '  "missingOrUnclear": ["Pending refund for incorrect milk in B426.", "Uncertainty about the substitution approval process in B426."]\n'
    '}\n`';

const taskE98fbaacExpectedKeyPointCount = 4;

/// Pre-fix `_stripMarkdownFences` + `trim()` used in the failing Sep 21 run.
String taskE98fbaacLegacyStrip(String raw) {
  if (!raw.startsWith('```')) {
    return raw;
  }
  final lines = raw.split('\n');
  if (lines.length < 2) {
    return raw;
  }
  final end = lines.lastWhere((l) => l.trim() == '```', orElse: () => '');
  if (end.isEmpty) {
    return lines.skip(1).join('\n').trim();
  }
  return lines.sublist(1, lines.length - 1).join('\n').trim();
}
