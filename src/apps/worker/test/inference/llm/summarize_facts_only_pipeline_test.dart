// NOT RUN — mock-runner tests for routing and evidence transport only; they do
// not show live semantic quality. Facts-only cases need:
// flutter test test/inference/llm/summarize_facts_only_pipeline_test.dart
//   --dart-define=SUMMARIZE_EVIDENCE_V2=true

import 'package:edgemint_worker/contracts/worker_error.dart';
import 'package:edgemint_worker/inference/llm/diagnostic/summarize_map_evidence_diagnostic_fixture.dart';
import 'package:edgemint_worker/inference/llm/diagnostic/summarize_map_prompt_variant.dart';
import 'package:edgemint_worker/inference/llm/formatted_prompt_builder.dart';
import 'package:edgemint_worker/inference/llm/hierarchical_summarize_pipeline.dart';
import 'package:edgemint_worker/inference/llm/prompt_templates.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/reduce_partial_envelope.dart';
import 'package:edgemint_worker/inference/llm/summarize_chunk_experiment.dart';
import 'package:edgemint_worker/inference/llm/summarize_evidence_pipeline.dart';
import 'package:edgemint_worker/inference/llm/summarize_inference_stage.dart';
import 'package:edgemint_worker/inference/llm/summarize_pipeline_mode.dart';
import 'package:edgemint_worker/inference/llm/summarize_reduce_budget.dart';
import 'package:edgemint_worker/inference/llm/summarize_task_constraints.dart';
import 'package:flutter_test/flutter_test.dart';

const _priorityFact = 'The customer says their main concern is the ignored preference.';
const _causeFact = 'The source says the cause of the change remains unexplained.';
const _extraFacts = [
  'Order A arrived late.',
  'Support promised a refund.',
  'The customer received the refund on day four.',
  'The customer declined an offer because of its minimum.',
];

String _mapJson(List<String> facts, {String priority = '', List<String> openItems = const []}) =>
    '{"schemaVersion":"2","facts":[${facts.map((f) => '"$f"').join(',')}],'
    '"openItems":[${openItems.map((f) => '"$f"').join(',')}],"priority":"$priority"}';

const _finalJson =
    '{"summary":"Short summary.","keyPoints":["a","b","c","d"],'
    '"mainComplaint":"The ignored preference.","suggestedImprovement":"Honor preferences.",'
    '"missingOrUnclear":["Cause of the change"]}';

final _constraints = SummarizeTaskConstraintsV1(keyPointCount: 4);

String _longSource() => List.generate(
      420,
      (i) => 'Sentence number $i records routine account activity without any issue.',
    ).join(' ');

bool _isMap(String prompt) => prompt.contains('Extract evidence from this chunk');
bool _isFinal(String prompt) =>
    prompt.contains('Produce the final customer-facing summary');
bool _isIntermediate(String prompt) =>
    prompt.contains('Merge these evidence partials');
bool _isConstraintRepair(String prompt) =>
    prompt.contains('Rewrite the invalid summary JSON');
bool _isJsonRepair(String prompt) => prompt.contains('Fix the following broken JSON');

QwenTaskProcessor _processor(
  List<String> prompts,
  String Function(String prompt) respond, {
  List<String>? logs,
}) =>
    QwenTaskProcessor(
      log: logs?.add,
      runner: (prompt) async {
        prompts.add(prompt);
        return respond(prompt);
      },
    );

void main() {
  group('Mode resolution and identity', () {
    test('default mode never selects facts-only', () {
      expect(defaultSummarizePipelineMode.isFactsOnly, isFalse);
      if (!SummarizeFactsOnlyPipeline.requested) {
        expect(resolveTextSummarizePipelineMode().isFactsOnly, isFalse);
      }
    });

    test('checkpoint identity separates modes and composes with chunk cap', () {
      final classified = summarizeCheckpointPromptVersion(factsOnly: false);
      final factsOnly = summarizeCheckpointPromptVersion(factsOnly: true);
      expect(classified, isNot(factsOnly));
      expect(classified, isNot(contains(SummarizeFactsOnlyPipeline.checkpointSuffix)));
      expect(factsOnly, contains(SummarizeFactsOnlyPipeline.checkpointSuffix));
      if (SummarizeChunkExperiment.active) {
        expect(factsOnly, contains('+srcCap'));
        expect(factsOnly.indexOf('+factsOnly'), lessThan(factsOnly.indexOf('+srcCap')));
      } else {
        expect(classified, PromptTemplates.version);
      }
    });

    test('facts-only with evidence v2 off rejects before inference', () async {
      if (SummarizeEvidencePipeline.enabled) {
        return;
      }
      final prompts = <String>[];
      final processor = _processor(prompts, (_) => _finalJson);
      await expectLater(
        processor.runSummarizeJsonTask(
          inputText: _longSource(),
          signingKey: 'test',
          constraints: _constraints,
          pipelineMode: SummarizePipelineMode.factsOnly,
        ),
        throwsA(isA<WorkerError>()),
      );
      expect(prompts, isEmpty);
    });
  });

  group('Prompt rendering (NOT RUN by default)', () {
    test('flag off keeps existing Map prompt; facts-only uses shared wording', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      String render({required bool factsOnly}) => PromptTemplates.summarizeMapChunk(
            chunkText: 'Chunk body.',
            chunkIndex: 0,
            totalChunks: 2,
            chunkId: 'a' * 64,
            userInstructions: 'Summarize.',
            constraints: _constraints,
            factsOnly: factsOnly,
          );
      final existing = render(factsOnly: false);
      final factsOnly = render(factsOnly: true);
      expect(existing, isNot(contains('Evidence recording')));
      expect(
        existing,
        PromptTemplates.summarizeMapChunkEvidenceDiagnostic(
          chunkText: 'Chunk body.',
          chunkIndex: 0,
          totalChunks: 2,
          chunkId: 'a' * 64,
          userInstructions: 'Summarize.',
          constraints: _constraints,
          promptVariant: SummarizeMapPromptVariant.current,
        ),
      );
      expect(
        factsOnly,
        PromptTemplates.summarizeMapChunkEvidenceDiagnostic(
          chunkText: 'Chunk body.',
          chunkIndex: 0,
          totalChunks: 2,
          chunkId: 'a' * 64,
          userInstructions: 'Summarize.',
          constraints: _constraints,
          promptVariant: SummarizeMapPromptVariant.factsOnly,
        ),
      );
    });

    test('intermediate facts-only keeps contract and no final counts', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final prompt = PromptTemplates.summarizeReduceIntermediate(
        partialSummariesJson: '[]',
        chunkCount: 2,
        userInstructions: 'Summarize.',
        constraints: _constraints,
        factsOnly: true,
      );
      expect(prompt, contains('"openItems":[],"priority":""'));
      expect(prompt, contains('intentional placeholders'));
      expect(prompt, contains('does not prove'));
      expect(prompt, isNot(contains('exactly 4')));
      expect(prompt, contains('Do not apply final word or key-point limits here.'));
    });

    test('final facts-only explains facts carry priority and unresolved matters', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final classified = PromptTemplates.summarizeReduceFinal(
        partialSummariesJson: '[]',
        chunkCount: 2,
        constraints: _constraints,
      );
      final factsOnly = PromptTemplates.summarizeReduceFinal(
        partialSummariesJson: '[]',
        chunkCount: 2,
        constraints: _constraints,
        factsOnly: true,
      );
      expect(classified, contains('from evidence priority field'));
      expect(factsOnly, isNot(contains('from evidence priority field')));
      expect(factsOnly, contains('intentional placeholders'));
      expect(factsOnly, contains('explicitly stating as\n  their priority'));
      expect(factsOnly, contains('a pending authorization is not a'));
    });
  });

  group('Budget uses the selected prompts (NOT RUN by default)', () {
    test('Map reservation and Reduce budget reflect facts-only prompts', () {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final processor = QwenTaskProcessor(runner: (_) async => '{}');
      final budget = processor.contextBudget;
      final reserve = processor.summarizePromptReserveTokens(
        userInstructions: 'Summarize.',
        constraints: _constraints,
        factsOnly: true,
      );
      final factsOnlyWrapper = budget.estimator.estimate(
        FormattedPromptBuilder.buildTaskPrompt(
          templateBody: PromptTemplates.summarizeMapChunk(
            chunkText: '',
            chunkIndex: 0,
            totalChunks: 999,
            chunkId: '0' * 64,
            userInstructions: 'Summarize.',
            constraints: _constraints,
            factsOnly: true,
          ),
          systemInstruction: budget.defaultSystemInstruction,
        ),
      );
      expect(reserve, greaterThanOrEqualTo(factsOnlyWrapper));

      final envelopes = [
        ReducePartialEnvelope.testSynthetic(
          chunkIndex: 0,
          partial: {'schemaVersion': '2', 'facts': [_priorityFact], 'openItems': [], 'priority': ''},
        ),
        ReducePartialEnvelope.testSynthetic(
          chunkIndex: 1,
          partial: {'schemaVersion': '2', 'facts': [_causeFact], 'openItems': [], 'priority': ''},
        ),
      ];
      final classifiedEval = SummarizeReduceBudget.evaluate(
        contextBudget: budget,
        envelopes: envelopes,
        userInstructions: 'Summarize.',
        constraints: _constraints,
        maxOutputTokens: 512,
        isFinalMerge: true,
      );
      final factsEval = SummarizeReduceBudget.evaluate(
        contextBudget: budget,
        envelopes: envelopes,
        userInstructions: 'Summarize.',
        constraints: _constraints,
        maxOutputTokens: 512,
        isFinalMerge: true,
        factsOnly: true,
      );
      expect(factsEval.formattedPromptTokens, isNot(classifiedEval.formattedPromptTokens));
    });
  });

  group('Assignment path with mock runner (NOT RUN by default)', () {
    test('single chunk still routes directPublic', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final prompts = <String>[];
      final logs = <String>[];
      final processor = _processor(prompts, (_) => _finalJson, logs: logs);
      await processor.runSummarizeJsonTask(
        inputText: 'Short source text.',
        signingKey: 'test',
        constraints: _constraints,
        pipelineMode: SummarizePipelineMode.factsOnly,
      );
      expect(prompts, hasLength(1));
      expect(_isMap(prompts.single), isFalse);
      expect(logs.any((l) => l.contains('[SUMMARIZE ROUTE] route=directPublic')), isTrue);
    });

    test('multi-chunk facts-only transports all facts into final Reduce', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final prompts = <String>[];
      final logs = <String>[];
      var mapCalls = 0;
      final processor = _processor(prompts, (prompt) {
        if (_isMap(prompt)) {
          mapCalls += 1;
          return mapCalls == 1
              ? _mapJson([_priorityFact, _causeFact, ..._extraFacts])
              : _mapJson(['Chunk $mapCalls had routine activity.']);
        }
        return _finalJson;
      }, logs: logs);
      final source = _longSource();
      await processor.runSummarizeJsonTask(
        inputText: source,
        signingKey: 'test',
        constraints: _constraints,
        pipelineMode: SummarizePipelineMode.factsOnly,
      );
      expect(mapCalls, greaterThan(1));
      expect(
        logs.any((l) => l.contains('[SUMMARIZE ROUTE] route=factsOnlyMapReduce')),
        isTrue,
      );
      final maps = prompts.where(_isMap).toList();
      expect(maps, hasLength(mapCalls));
      for (final map in maps) {
        expect(map, contains('Evidence recording'));
        expect(map, isNot(contains(summarizeMapEvidenceDiagnosticSourceNarrative)));
      }
      expect(prompts.any((p) => p.contains('Classify evidence statements')), isFalse);
      final finals = prompts.where(_isFinal).toList();
      expect(finals, isNotEmpty);
      final finalPrompt = finals.last;
      expect(finalPrompt, contains(_priorityFact));
      expect(finalPrompt, contains(_causeFact));
      for (final fact in _extraFacts) {
        expect(finalPrompt, contains(fact));
      }
      expect(finalPrompt, contains('intentional placeholders'));
    });

    test('intermediate reduce keeps facts-only contract', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final stages = <SummarizeInferenceStage>[];
      final prompts = <String>[];
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: QwenTaskProcessor().contextBudget,
        mode: SummarizePipelineMode.factsOnly,
        runPromptJson: (prompt, {required inferenceStage}) async {
          stages.add(inferenceStage);
          prompts.add(prompt);
          return {'schemaVersion': '2', 'facts': ['merged'], 'openItems': [], 'priority': ''};
        },
      );
      final envelopes = [
        for (var i = 0; i < 2; i++)
          ReducePartialEnvelope.testSynthetic(
            chunkIndex: i,
            partial: {
              'schemaVersion': '2',
              'facts': [..._extraFacts, 'Chunk $i fact.'],
              'openItems': [],
              'priority': '',
            },
          ),
      ];
      final merged = await pipeline.reducePartials(envelopes, isFinalMerge: false);
      expect(stages.single, SummarizeInferenceStage.intermediateEvidence);
      expect(_isIntermediate(prompts.single), isTrue);
      expect(prompts.single, isNot(contains('exactly 4')));
      expect(merged['openItems'], isEmpty);
    });

    test('intermediate reduce populating priority is rejected, not blanked', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final pipeline = HierarchicalSummarizePipeline(
        contextBudget: QwenTaskProcessor().contextBudget,
        mode: SummarizePipelineMode.factsOnly,
        runPromptJson: (prompt, {required inferenceStage}) async =>
            {'schemaVersion': '2', 'facts': ['m'], 'openItems': [], 'priority': 'p'},
      );
      final envelopes = [
        for (var i = 0; i < 2; i++)
          ReducePartialEnvelope.testSynthetic(
            chunkIndex: i,
            partial: {'schemaVersion': '2', 'facts': [..._extraFacts], 'openItems': [], 'priority': ''},
          ),
      ];
      await expectLater(
        pipeline.reducePartials(envelopes, isFinalMerge: false),
        throwsA(
          isA<WorkerError>().having(
            (e) => e.message,
            'message',
            contains('facts_only_contract_mismatch'),
          ),
        ),
      );
    });

    test('JSON repair output must meet the same facts-only contract', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final processor = _processor([], (prompt) {
        if (_isJsonRepair(prompt)) {
          return _mapJson(['Repaired fact.'], priority: 'classified anyway');
        }
        if (_isMap(prompt)) {
          return '{"schemaVersion":"2","facts":["broken"';
        }
        return _finalJson;
      });
      await expectLater(
        processor.runSummarizeJsonTask(
          inputText: _longSource(),
          signingKey: 'test',
          constraints: _constraints,
          pipelineMode: SummarizePipelineMode.factsOnly,
        ),
        throwsA(isA<WorkerError>()),
      );
    });

    test('one corrective budget is shared across all chunks', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final prompts = <String>[];
      var mapCalls = 0;
      final processor = _processor(prompts, (prompt) {
        if (_isJsonRepair(prompt)) {
          return _mapJson(['Repaired fact.']);
        }
        if (_isMap(prompt)) {
          mapCalls += 1;
          return mapCalls <= 2 ? 'not json at all' : _mapJson(['Fact.']);
        }
        return _finalJson;
      });
      await expectLater(
        processor.runSummarizeJsonTask(
          inputText: _longSource(),
          signingKey: 'test',
          constraints: _constraints,
          pipelineMode: SummarizePipelineMode.factsOnly,
        ),
        throwsA(isA<WorkerError>()),
      );
      expect(prompts.where(_isJsonRepair), hasLength(1));
    });

    test('final constraint repair reads facts evidence, not source text', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final prompts = <String>[];
      var finalCalls = 0;
      final processor = _processor(prompts, (prompt) {
        if (_isConstraintRepair(prompt)) {
          return _finalJson;
        }
        if (_isMap(prompt)) {
          return _mapJson([_priorityFact, _causeFact]);
        }
        finalCalls += 1;
        return '{"summary":"s","keyPoints":["only one"],"mainComplaint":"m",'
            '"suggestedImprovement":"i","missingOrUnclear":[]}';
      });
      final source = _longSource();
      await processor.runSummarizeJsonTask(
        inputText: source,
        signingKey: 'test',
        constraints: _constraints,
        pipelineMode: SummarizePipelineMode.factsOnly,
      );
      final repair = prompts.where(_isConstraintRepair).single;
      expect(repair, contains('using the merged evidence below'));
      expect(repair, contains(_priorityFact));
      expect(repair, contains(_causeFact));
      expect(repair, contains('intentional placeholders'));
      expect(repair, isNot(contains('Source text:')));
      expect(repair, isNot(contains(source.substring(0, 60))));
      expect(finalCalls, 1);
    });

    test('flag off keeps existing evidence route', () async {
      if (!SummarizeEvidencePipeline.enabled) {
        return;
      }
      final prompts = <String>[];
      final logs = <String>[];
      final processor = _processor(prompts, (prompt) {
        if (_isMap(prompt)) {
          return '{"schemaVersion":"2","facts":["Fact."],"openItems":[],"priority":""}';
        }
        return _finalJson;
      }, logs: logs);
      await processor.runSummarizeJsonTask(
        inputText: _longSource(),
        signingKey: 'test',
        constraints: _constraints,
      );
      expect(
        logs.any((l) => l.contains('route=existingEvidenceMapReduce')),
        isTrue,
      );
      for (final map in prompts.where(_isMap)) {
        expect(map, isNot(contains('Evidence recording')));
      }
    });
  });
}
