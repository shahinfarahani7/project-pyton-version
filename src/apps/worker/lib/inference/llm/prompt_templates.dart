import 'dart:convert';

import 'context_budget_manager.dart';
import 'diagnostic/summarize_map_prompt_variant.dart';
import 'summarize_constraint_renderer.dart';
import 'summarize_evidence_pipeline.dart';
import 'summarize_task_constraints.dart';

abstract final class PromptTemplates {
  static String get version => SummarizeEvidencePipeline.activePromptVersion;

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

  static const _evidenceKeys = 'schemaVersion, facts, openItems, priority';

  static const _evidenceShape =
      '{"schemaVersion":"2","facts":["..."],"openItems":["..."],"priority":""}';

  static String _evidenceKeyGuard() =>
      'Return one JSON object with exactly these four keys and no others: '
      '$_evidenceKeys.';

  static String _answerNow(String subject) =>
      'Now write the JSON object about the $subject above. '
      'Use your own short wording, never a sentence copied from it.';

  static String _customerInstructionsBlock(String? userInstructions) {
    if (userInstructions == null || userInstructions.isEmpty) {
      return '';
    }
    return '\nCustomer instructions:\n$userInstructions\n';
  }

  static String _customerInstructionsBlockVerbatim(String? userInstructions) {
    if (userInstructions == null || userInstructions.isEmpty) {
      return '';
    }
    return '\nCustomer instructions (apply when reading this chunk; verbatim):\n'
        '$userInstructions\n';
  }

  static String _mapSizeLimit() =>
      'Keep the whole JSON under $_maxJsonOutputChars characters; shorten wording '
      'as needed to fit. If critical facts do not fit, prioritize amounts, explicit '
      'resolutions, entity references, and customer-stated priority over generic prose.';

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
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    int evidenceTarget = 6,
    bool factsOnly = false,
  }) {
    _assertFactsOnlyAllowed(factsOnly);
    if (SummarizeEvidencePipeline.enabled) {
      return _summarizeMapChunkEvidenceV2(
        chunkText: chunkText,
        chunkIndex: chunkIndex,
        totalChunks: totalChunks,
        chunkId: chunkId,
        userInstructions: userInstructions,
        constraints: constraints,
        promptVariant: factsOnly
            ? SummarizeMapPromptVariant.factsOnly
            : SummarizeMapPromptVariant.current,
      );
    }
    final constraintBlock = SummarizeConstraintRenderer.mapGuidanceBlock(constraints);
    return '''
Extract evidence from this chunk of a longer document. This is an intermediate
step, not the final customer-facing summary.
${_summaryKeyGuard()}
$_summaryShape

Stage rules (intermediate):
- keyPoints: atomic facts stated in this chunk (amounts, order ids, dates,
  pending vs promised vs received vs declined). Prefer at most $evidenceTarget
  distinct points, but include all critical explicit updates even if you must
  shorten wording to fit the JSON size limit.
- summary: one short orientation sentence for this chunk only, or "" if
  keyPoints already carry the facts. Do not write a final case summary.
- mainComplaint: populate ONLY if this chunk explicitly states a prioritized
  customer concern (e.g. "my main complaint is…", "my main concern is…").
  Otherwise "".
- suggestedImprovement: populate ONLY if this chunk explicitly states a fix;
  otherwise "".
- missingOrUnclear: open questions or pending/promised-not-received items
  stated in this chunk. If this chunk explicitly resolves an earlier question
  (refund received, authorization released, payment confirmed), put the
  resolution in keyPoints and do NOT list it here.

Do not add facts not present in this chunk. Do not combine unrelated orders or
financial events in one keyPoint. Copy numbers, dates, and ids exactly.
Every string value must be a string and every array value must be an array.

Final output constraints below apply to the REDUCE stage, not to this map
output: do not enforce final key-point count or final word limit here.
$constraintBlock${_customerInstructionsBlockVerbatim(userInstructions)}${_mapSizeLimit()}
Chunk metadata: chunkIndex=$chunkIndex totalChunks=$totalChunks chunkId=$chunkId

Chunk text:
---
$chunkText
---
${_answerNow('chunk')}
/no_think
''';
  }

  /// Isolated Map diagnostic only; production Map uses [summarizeMapChunk].
  static String summarizeMapChunkEvidenceDiagnostic({
    required String chunkText,
    required int chunkIndex,
    required int totalChunks,
    required String chunkId,
    required SummarizeMapPromptVariant promptVariant,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
  }) =>
      _summarizeMapChunkEvidenceV2(
        chunkText: chunkText,
        chunkIndex: chunkIndex,
        totalChunks: totalChunks,
        chunkId: chunkId,
        userInstructions: userInstructions,
        constraints: constraints,
        promptVariant: promptVariant,
      );

  /// Facts-only experiment Step 2; receives only the extracted statements.
  static String factsClassificationDiagnostic({required List<String> facts}) {
    final numbered = [
      for (var index = 0; index < facts.length; index++)
        '[$index] ${jsonEncode(facts[index])}',
    ].join('\n');
    return '''
Classify evidence statements recorded by an earlier extraction step. You see only
the numbered statements below; you do not have the original document.
Return one JSON object with exactly these three keys and no others: schemaVersion, priority, openItems.
Shape:
{"schemaVersion":"diag_classify_1","priority":{"text":"...","supportingFactIndexes":[0]},"openItems":[{"text":"...","supportingFactIndexes":[0]}]}

Rules:
- priority.text: the customer's explicitly stated main concern as recorded in a
  statement below, as a short paraphrase or quotation. If no statement records one,
  use "" with supportingFactIndexes [].
- openItems: one entry per matter that a statement below says is still unresolved
  or unexplained. Keep the matter that statement names; do not turn it into a
  question about a different event, and do not list anything a statement records as
  received, completed, released, declined, or otherwise resolved. [] if none.
- supportingFactIndexes: the bracketed numbers of the statements that record that
  priority or open item. Use only numbers shown below.
- Do not add information that no statement contains.

Statements:
$numbered

Write the JSON object.
/no_think
''';
  }

  static String _mapRepeatRule(SummarizeMapPromptVariant variant) =>
      switch (variant) {
        SummarizeMapPromptVariant.current =>
          '  string. Split unrelated events or decisions into separate entries. Do not repeat\n'
              '  the same fact in different wording.',
        SummarizeMapPromptVariant.explicitUpdates ||
        SummarizeMapPromptVariant.explicitUpdatesNoFieldMapping =>
          '  string. Split unrelated events or decisions into separate entries. Do not restate\n'
              '  an unchanged status in different wording; a later explicit update to the same\n'
              '  event is a separate fact (see field assignment).',
        SummarizeMapPromptVariant.factsOnly =>
          '  string. Split unrelated events or decisions into separate entries. Do not restate\n'
              '  an unchanged status in different wording; a later explicit update to the same\n'
              '  event is a separate fact (see evidence recording).',
      };

  static String _mapEvidenceShape(SummarizeMapPromptVariant variant) =>
      switch (variant) {
        SummarizeMapPromptVariant.factsOnly =>
          '{"schemaVersion":"2","facts":["..."],"openItems":[],"priority":""}',
        _ => _evidenceShape,
      };

  static String _mapFieldRules(SummarizeMapPromptVariant variant) =>
      switch (variant) {
        SummarizeMapPromptVariant.current =>
          '- Short faithful quotations are allowed for exact attribution or priority; do not\n'
              '  copy paragraph-length text into one string.\n'
              '- openItems: one concise string per unresolved question in this chunk only; state\n'
              '  resolutions as facts instead. [] if none.\n'
              '- priority: concise paraphrase or short quotation of explicit customer priority;\n'
              '  otherwise "".',
        SummarizeMapPromptVariant.explicitUpdates ||
        SummarizeMapPromptVariant.explicitUpdatesNoFieldMapping =>
          '- Field assignment — assign statements by their role as follows:\n'
              '  facts: events, amounts, statuses, and attribution (who claimed, denied, or\n'
              '  provided evidence). When the source gives a later explicit update to the same\n'
              '  event (promised then received with stated timing, pending then released or\n'
              '  completed, offered then declined with reason), record that update as its own\n'
              '  fact; it is not a redundant repeat of the earlier status.\n'
              '  openItems: only what the source itself still leaves unresolved or unexplained;\n'
              '  do not infer an open question from an event the source already resolves. [] if none.\n'
              '  priority: the customer\'s explicitly stated main concern, paraphrase or short\n'
              '  quotation; put that concern here only — do not restate the same concern sentence\n'
              '  in facts[]. Keep in facts the specific events, claims, denials, and records\n'
              '  that support the concern. "" if none.\n'
              '${_mapInstructionUseRule(variant)}\n'
              '- Short faithful quotations are allowed for exact attribution or priority; do not\n'
              '  copy paragraph-length text into one string.',
        SummarizeMapPromptVariant.factsOnly =>
          '- Evidence recording — this step records evidence only; a later step classifies it:\n'
              '  facts: events, amounts, statuses, and attribution (who claimed, denied, or\n'
              '  provided evidence). When the source gives a later explicit update to the same\n'
              '  event (promised then received with stated timing, pending then released or\n'
              '  completed, offered then declined with reason), record that update as its own\n'
              '  fact; it is not a redundant repeat of the earlier status.\n'
              "  When the source states the customer's main concern, record it as a fact that\n"
              '  attributes it to the customer (for example "The customer says their main\n'
              '  concern is ...").\n'
              '  When the source states that something remains unresolved or unexplained, record\n'
              '  that statement as a fact about that same matter; do not turn it into a question\n'
              '  and do not attach it to an event the source resolves.\n'
              '  openItems is [] and priority is "" at this step.\n'
              '- The customer instructions below describe the final answer. At this step use\n'
              '  them only to decide which evidence is relevant; record that evidence in facts\n'
              '  and do not write summary, keyPoints, mainComplaint, suggestedImprovement, or\n'
              '  missingOrUnclear.\n'
              '- Short faithful quotations are allowed for exact attribution or priority; do not\n'
              '  copy paragraph-length text into one string.',
      };

  static String _mapInstructionUseRule(SummarizeMapPromptVariant variant) =>
      switch (variant) {
        SummarizeMapPromptVariant.explicitUpdatesNoFieldMapping =>
          "- Use the customer's instructions to identify relevant evidence. Field values\n"
              '  must describe the source content, not name output fields. Put the stated\n'
              '  main concern in priority and explicitly unresolved matters in openItems.',
        _ =>
          '- Customer instructions below that mention mainComplaint or missingOrUnclear apply\n'
              '  at this Map stage as priority and openItems; leave that instruction text verbatim.',
      };

  static String _summarizeMapChunkEvidenceV2({
    required String chunkText,
    required int chunkIndex,
    required int totalChunks,
    required String chunkId,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    SummarizeMapPromptVariant promptVariant = SummarizeMapPromptVariant.current,
  }) {
    final constraintBlock = SummarizeConstraintRenderer.evidenceMapGuidanceBlock(constraints);
    return '''
Extract evidence from this chunk of a longer document. Intermediate step only —
NOT the final customer-facing summary.
${_evidenceKeyGuard()}
Shape:
${_mapEvidenceShape(promptVariant)}

Rules:
- facts and openItems are JSON arrays of strings only, never objects or nested values.
- Each facts[] entry is one distinct fact in one short sentence (aim for about 15–25
  words when practical; use more when needed for event identity, amounts, dates,
  status, attribution, denial, or a decision's reason). Extract facts; do not copy
  or continue the source narrative. Do not put a paragraph or several events in one
${_mapRepeatRule(promptVariant)}
${_mapFieldRules(promptVariant)}
- After distinct relevant evidence, close the arrays and object. Do not pad to a
  target count or omit relevant facts to meet a count.
- Not a case summary or final answer; final word/key-point limits apply only at
  final reduce.

Format example only — unrelated to this input; do not copy these facts:
{"schemaVersion":"2","facts":["Ticket R17 was closed on June 4.","The customer declined a replacement because it required another appointment."],"openItems":[],"priority":""}

Do not add facts not present in this chunk. Preserve numbers and identifiers exactly.
$constraintBlock${_customerInstructionsBlockVerbatim(userInstructions)}
Soft JSON size target: about $_maxJsonOutputChars characters. Shorten wording before omitting
critical amounts, decisions, reasons, attributions, or explicit priority. If critical
facts cannot fit, include the highest-priority explicit statements and omit lower-priority
detail — do not fabricate replacements.

Chunk metadata: chunkIndex=$chunkIndex totalChunks=$totalChunks chunkId=$chunkId

Chunk text:
---
$chunkText
---
Write the JSON object for this chunk.
/no_think
''';
  }

  static String summarizeReduceIntermediate({
    required String partialSummariesJson,
    required int chunkCount,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    bool factsOnly = false,
  }) {
    _assertFactsOnlyAllowed(factsOnly);
    if (factsOnly) {
      return _summarizeReduceIntermediateFactsOnly(
        partialSummariesJson: partialSummariesJson,
        chunkCount: chunkCount,
        userInstructions: userInstructions,
        constraints: constraints,
      );
    }
    if (SummarizeEvidencePipeline.enabled) {
      return _summarizeReduceIntermediateEvidenceV2(
        partialSummariesJson: partialSummariesJson,
        chunkCount: chunkCount,
        userInstructions: userInstructions,
        constraints: constraints,
      );
    }
    final guidanceBlock = SummarizeConstraintRenderer.mapGuidanceBlock(constraints);
    return '''
Combine these partial summaries into one merged intermediate summary for further
merging. This is not the final customer-facing answer.
${_summaryKeyGuard()}
$_summaryShape

Merge keyPoints without losing distinct facts (amounts, ids, pending vs received
vs promised vs declined). Do not invent facts.

missingOrUnclear: include only questions still unresolved after reading ALL
partials below. Remove an earlier uncertainty when another partial explicitly
resolves the same event (refund received, pending authorization released, single
confirmed payment). Keep unrelated open items. If partials conflict without an
explicit resolution, state the conflict in missingOrUnclear.

mainComplaint: use explicit customer priority text from any partial; if none,
"". Do not default to the first partial's generic complaint.

suggestedImprovement: one practical action if clearly supported; otherwise "".

Partials carry sourceChunkIndexes and processedCharRanges assigned by the
system. Source order is document order, NOT proof of event chronology—prefer
explicit resolution statements over earlier pending/promised wording.

Do not apply final word-count or final key-point-count limits in this
intermediate merge—preserve evidence for the next merge step.
${_customerInstructionsBlockVerbatim(userInstructions)}$guidanceBlock${_mapSizeLimit()}
Partial summaries ($chunkCount groups):
---
$partialSummariesJson
---
${_answerNow('partial summaries')}
/no_think
''';
  }

  static String _summarizeReduceIntermediateEvidenceV2({
    required String partialSummariesJson,
    required int chunkCount,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
  }) {
    final guidanceBlock =
        SummarizeConstraintRenderer.evidenceMapGuidanceBlock(constraints);
    return '''
Merge these evidence partials into one intermediate evidence object for further
merging. NOT the final customer-facing answer.
${_evidenceKeyGuard()}
Shape: $_evidenceShape

Rules:
- facts and openItems are JSON arrays of strings only. Never put objects, numbers,
  null, or nested arrays inside them.
- Include every distinct fact string from all partials. Remove only exact duplicate strings.
  Do not repeat or restate a fact already listed.
- Include every openItem string from all partials. Remove only exact duplicate strings.
  Do NOT drop openItems because another fact "seems related". Do NOT resolve or
  close openItems at this stage.
- priority: if exactly one partial has non-empty priority, keep it. If multiple
  partials state priority differently, preserve each distinct statement joined as
  "first ; second" in source order of partials — do not rank or choose between them.
- Do not create summary, keyPoints, mainComplaint, suggestedImprovement, or
  missingOrUnclear. Do not apply final word or key-point limits here.

Partials include sourceChunkIndexes assigned by the system for document coverage.
Those indexes show which chunk groups contributed; they do NOT prove each generated
fact is supported. Do not treat later chunk groups as automatically authoritative.
${_customerInstructionsBlockVerbatim(userInstructions)}$guidanceBlock
Soft JSON size target: about $_maxJsonOutputChars characters. Compress phrasing only; do not drop
distinct facts or openItems. You cannot preserve unlimited distinct evidence in
fixed-size output — if necessary, shorten strings but keep separate facts separate.

Partial evidence ($chunkCount groups):
---
$partialSummariesJson
---
Write the merged JSON object.
/no_think
''';
  }

  static void _assertFactsOnlyAllowed(bool factsOnly) {
    if (factsOnly && !SummarizeEvidencePipeline.enabled) {
      throw StateError('Facts-only summarize prompts require SUMMARIZE_EVIDENCE_V2=true');
    }
  }

  static const _factsOnlyEvidenceNote =
      '- This evidence is facts-only: every source statement, including the customer\'s\n'
      '  stated priority and matters the source says remain unresolved, is in facts.\n'
      '  Empty openItems and priority fields are intentional placeholders, not evidence\n'
      '  that the source has no priority or unresolved matters.';

  static const _factsOnlyStatusRules =
      '- When facts give explicit updates about the SAME event, the explicitly later\n'
      '  update decides its status; do not assume document, chunk, or list order decides\n'
      '  truth.\n'
      '- Keep statuses as the facts state them: a pending authorization is not a\n'
      '  completed charge; a promised refund is not received unless a fact records its\n'
      '  receipt, and a refund a fact records as received is not merely pending; a\n'
      '  declined offer is not accepted.\n'
      '- Keep each claim and denial attributed to the speaker the facts name.';

  static String _finalFactsOnlyRules(String keyPointLine) => '''
$_factsOnlyEvidenceNote
- Use the facts from every partial below; do not invent facts.
$keyPointLine
- mainComplaint: the concern the facts record the customer explicitly stating as
  their priority; preserve every component the customer named.
- suggestedImprovement: one practical recommendation grounded in mainComplaint and facts.
- missingOrUnclear: only matters the facts record as still unresolved or unexplained.
  Do not list anything the facts record as received, declined with a stated reason,
  completed, or released.
$_factsOnlyStatusRules
- Short faithful quotations remain permitted when reflecting explicit priority or denials.
''';

  static String _summarizeReduceIntermediateFactsOnly({
    required String partialSummariesJson,
    required int chunkCount,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
  }) {
    final guidanceBlock =
        SummarizeConstraintRenderer.evidenceMapGuidanceBlock(constraints);
    return '''
Merge these evidence partials into one intermediate evidence object for further
merging. NOT the final customer-facing answer.
${_evidenceKeyGuard()}
Shape: {"schemaVersion":"2","facts":["..."],"openItems":[],"priority":""}

Rules:
- facts is a JSON array of strings only. Never put objects, numbers, null, or
  nested arrays inside it.
$_factsOnlyEvidenceNote
- Include every distinct fact from all partials. Remove only exact duplicate strings.
  You may shorten wording, but keep event identity, amounts, dates and timing,
  attribution (who claimed, denied, or provided evidence), decisions and their
  reasons, the customer's stated priority, and unresolved matters as facts.
- Keep a later explicit update to an event as its own fact, distinguishable from the
  earlier status. The order of partials or facts does not prove that one statement
  supersedes another.
- openItems is [] and priority is "" in the merged object; do not classify here.
- Do not create summary, keyPoints, mainComplaint, suggestedImprovement, or
  missingOrUnclear. Do not apply final word or key-point limits here.

Partials include sourceChunkIndexes assigned by the system for document coverage.
Those indexes show which chunk groups contributed; they do NOT prove each generated
fact is supported. Do not treat later chunk groups as automatically authoritative.
${_customerInstructionsBlockVerbatim(userInstructions)}$guidanceBlock
Soft JSON size target: about $_maxJsonOutputChars characters. Compress phrasing only; do not drop
distinct facts. You cannot preserve unlimited distinct evidence in fixed-size
output — if necessary, shorten strings but keep separate facts separate.

Partial evidence ($chunkCount groups):
---
$partialSummariesJson
---
Write the merged JSON object.
/no_think
''';
  }

  /// Final constraint repair for facts-only Map/Reduce; reads the same merged
  /// evidence the final Reduce received instead of the source text.
  static String summaryConstraintRepairFromFactsEvidence({
    required String evidenceJson,
    required String invalidSummaryJson,
    required String validationIssue,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
  }) {
    _assertFactsOnlyAllowed(true);
    final constraintBlock = SummarizeConstraintRenderer.promptBlock(constraints);
    final keyPointCount = constraints?.keyPointCount ?? 3;
    return '''
Rewrite the invalid summary JSON using the merged evidence below.
${_summaryKeyGuard()}
{"summary":"...","keyPoints":[${List.filled(keyPointCount, '"..."').join(',')}],"mainComplaint":"...","suggestedImprovement":"...","missingOrUnclear":["..."]}
Fix these validation failures: $validationIssue
$constraintBlock$_factsOnlyEvidenceNote
- mainComplaint comes from the priority the facts record; missingOrUnclear only from
  matters the facts record as still unresolved. Do not invent facts.
$_factsOnlyStatusRules
${_customerInstructionsBlock(userInstructions)}${_sizeLimit()}
Invalid JSON:
---
$invalidSummaryJson
---
Merged evidence:
---
$evidenceJson
---
${_answerNow('merged evidence')}
/no_think
''';
  }

  static String summarizeReduceFinal({
    required String partialSummariesJson,
    required int chunkCount,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    bool factsOnly = false,
  }) {
    _assertFactsOnlyAllowed(factsOnly);
    if (SummarizeEvidencePipeline.enabled) {
      return _summarizeReduceFinalEvidenceV2(
        partialSummariesJson: partialSummariesJson,
        chunkCount: chunkCount,
        userInstructions: userInstructions,
        constraints: constraints,
        factsOnly: factsOnly,
      );
    }
    final constraintBlock = SummarizeConstraintRenderer.promptBlock(constraints);
    final keyPointLine = constraints?.keyPointCount != null
        ? 'Return exactly ${constraints!.keyPointCount} distinct key points.\n'
        : 'Merge overlapping key points without losing distinct facts.\n';
    return '''
Combine the partial summaries into one final summary.
Produce the final customer-facing summary. Apply customer instructions and
structured output requirements below.
${_summaryKeyGuard()}
$_summaryShape
Merge overlapping key points, preserve factual coverage, and do not invent facts.
$keyPointLine

missingOrUnclear: include only questions still unresolved after reading ALL
partials below. Remove an earlier uncertainty when another partial explicitly
resolves the same event (refund received, pending authorization released, single
confirmed payment). Keep unrelated open items. If partials conflict without an
explicit resolution, state the conflict in missingOrUnclear.

mainComplaint: use explicit customer priority text from any partial; if none,
derive from the merged facts. Do not default to the first partial's generic
complaint when a later partial states explicit customer priority.

suggestedImprovement: one practical action addressing the main complaint if
clearly supported; otherwise derive one from the merged facts.

Partials carry sourceChunkIndexes and processedCharRanges assigned by the
system. Source order is document order, NOT proof of event chronology—prefer
explicit resolution statements over earlier pending/promised wording.

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

  static String _summarizeReduceFinalEvidenceV2({
    required String partialSummariesJson,
    required int chunkCount,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
    bool factsOnly = false,
  }) {
    final constraintBlock = SummarizeConstraintRenderer.promptBlock(constraints);
    final keyPointLine = constraints?.keyPointCount != null
        ? '- keyPoints: exactly ${constraints!.keyPointCount} distinct points drawn from evidence; preserve\n'
          '  distinct entities/events — do not collapse unrelated payments, refunds, or orders.\n'
        : '- keyPoints: distinct points drawn from evidence; preserve distinct entities/events.\n';
    final rules = factsOnly
        ? _finalFactsOnlyRules(keyPointLine)
        : '''
- Use only merged evidence facts and openItems; do not invent facts.
$keyPointLine
- mainComplaint: reflect explicit customer priority from evidence priority field;
  preserve every component the customer explicitly prioritized (not only the first).
- suggestedImprovement: one practical recommendation grounded in mainComplaint and facts.
- missingOrUnclear: unresolved items only. Do not list items evidence facts mark as
  received, declined with stated reason, completed, or released. When two facts give
  explicit updates about the SAME entity and issue, prefer the explicit update; do
  not assume document order or chunk order decides truth. Unresolved contradictions
  stay in missingOrUnclear when evidence shows no resolution.
- Short faithful quotations remain permitted when reflecting explicit priority or denials.
''';
    return '''
Produce the final customer-facing summary from merged evidence below.
${_summaryKeyGuard()}
Shape: $_summaryShape

$constraintBlock
Rules:
$rules
${_customerInstructionsBlockVerbatim(userInstructions)}
Soft JSON size target: about $_maxJsonOutputChars characters.

Merged evidence ($chunkCount groups):
---
$partialSummariesJson
---
Write the final JSON object.
/no_think
''';
  }

  /// Backward-compatible alias for final reduce prompts.
  static String summarizeReduce({
    required String partialSummariesJson,
    required int chunkCount,
    String? userInstructions,
    SummarizeTaskConstraintsV1? constraints,
  }) =>
      summarizeReduceFinal(
        partialSummariesJson: partialSummariesJson,
        chunkCount: chunkCount,
        userInstructions: userInstructions,
        constraints: constraints,
      );

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
