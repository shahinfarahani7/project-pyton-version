import 'dart:convert';
import 'dart:io';

import 'package:edgemint_worker/runtime/execution_plan_runner.dart';
import 'package:edgemint_worker/runtime/vision_runtime_catalog.dart';
import 'package:edgemint_worker/tasks/handlers/direct_prompt_handler.dart';
import 'package:edgemint_worker/tasks/handlers/document_handlers.dart';
import 'package:edgemint_worker/tasks/handlers/lightweight_vision_handlers.dart';
import 'package:edgemint_worker/tasks/handlers/ocr_extract_text_handler.dart';
import 'package:edgemint_worker/tasks/handlers/vision_handlers.dart';
import 'package:edgemint_worker/tasks/mobile_task_dispatcher.dart';
import 'package:edgemint_worker/tasks/task_type_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Table-driven contract for every worker-executable public route (representatives
/// plus neighboring family IDs that must not drift to the wrong handler).
class _RouteRow {
  const _RouteRow({
    required this.publicId,
    required this.internalCapability,
    required this.handlerType,
    required this.requiresOcr,
    required this.requiresLlm,
    required this.imageInput,
    this.requiresVisionRuntime = false,
    this.expectMapReducePlan = false,
    this.expectVisionPlan = false,
    this.expectHandlerOnOcrStage = false,
  });

  final String publicId;
  final String internalCapability;
  final Type handlerType;
  final bool requiresOcr;
  final bool requiresLlm;
  final bool imageInput;
  final bool requiresVisionRuntime;
  final bool expectMapReducePlan;
  final bool expectVisionPlan;
  final bool expectHandlerOnOcrStage;
}

void main() {
  final dispatcher = MobileTaskDispatcher();

  const routes = <_RouteRow>[
    _RouteRow(
      publicId: 'document.ocr',
      internalCapability: TaskTypeMapper.ocrExtractText,
      handlerType: OcrExtractTextHandler,
      requiresOcr: true,
      requiresLlm: false,
      imageInput: true,
      expectHandlerOnOcrStage: true,
    ),
    _RouteRow(
      publicId: 'ocr.receipt',
      internalCapability: TaskTypeMapper.ocrExtractText,
      handlerType: OcrExtractTextHandler,
      requiresOcr: true,
      requiresLlm: false,
      imageInput: true,
      expectHandlerOnOcrStage: true,
    ),
    _RouteRow(
      publicId: 'document.extract',
      internalCapability: TaskTypeMapper.documentExtract,
      handlerType: DocumentExtractHandler,
      requiresOcr: true,
      requiresLlm: true,
      imageInput: true,
    ),
    _RouteRow(
      publicId: 'extract.amount',
      internalCapability: TaskTypeMapper.documentExtract,
      handlerType: DocumentExtractHandler,
      requiresOcr: true,
      requiresLlm: true,
      imageInput: true,
    ),
    _RouteRow(
      publicId: 'document.classify',
      internalCapability: TaskTypeMapper.documentClassify,
      handlerType: DocumentClassifyHandler,
      requiresOcr: true,
      requiresLlm: true,
      imageInput: true,
    ),
    _RouteRow(
      publicId: 'document.summarize',
      internalCapability: TaskTypeMapper.documentSummarize,
      handlerType: DocumentSummarizeHandler,
      requiresOcr: true,
      requiresLlm: true,
      imageInput: true,
      expectMapReducePlan: true,
    ),
    _RouteRow(
      publicId: 'text.classify',
      internalCapability: TaskTypeMapper.textClassify,
      handlerType: TextClassifyHandler,
      requiresOcr: false,
      requiresLlm: true,
      imageInput: false,
    ),
    _RouteRow(
      publicId: 'moderation.profanity',
      internalCapability: TaskTypeMapper.textClassify,
      handlerType: TextClassifyHandler,
      requiresOcr: false,
      requiresLlm: true,
      imageInput: false,
    ),
    _RouteRow(
      publicId: 'nlp.spam_fraud_classification',
      internalCapability: TaskTypeMapper.textClassify,
      handlerType: TextClassifyHandler,
      requiresOcr: false,
      requiresLlm: true,
      imageInput: false,
    ),
    _RouteRow(
      publicId: 'text.summarize',
      internalCapability: TaskTypeMapper.textSummarize,
      handlerType: TextSummarizeHandler,
      requiresOcr: false,
      requiresLlm: true,
      imageInput: false,
      expectMapReducePlan: true,
    ),
    _RouteRow(
      publicId: 'text.direct',
      internalCapability: TaskTypeMapper.textDirect,
      handlerType: DirectPromptHandler,
      requiresOcr: false,
      requiresLlm: true,
      imageInput: false,
    ),
    _RouteRow(
      publicId: 'image.classify',
      internalCapability: TaskTypeMapper.visionAnalyze,
      handlerType: VisionAnalyzeHandler,
      requiresOcr: false,
      requiresLlm: true,
      imageInput: true,
      expectVisionPlan: true,
    ),
    _RouteRow(
      publicId: 'safety.nsfw_detection',
      internalCapability: TaskTypeMapper.visionAnalyze,
      handlerType: VisionAnalyzeHandler,
      requiresOcr: false,
      requiresLlm: true,
      imageInput: true,
      expectVisionPlan: true,
    ),
    _RouteRow(
      publicId: 'llm.image_output_safety',
      internalCapability: TaskTypeMapper.visionAnalyze,
      handlerType: VisionAnalyzeHandler,
      requiresOcr: false,
      requiresLlm: true,
      imageInput: true,
      expectVisionPlan: true,
    ),
    _RouteRow(
      publicId: 'image.remove_background',
      internalCapability: TaskTypeMapper.removeBackground,
      handlerType: RemoveBackgroundHandler,
      requiresOcr: false,
      requiresLlm: false,
      requiresVisionRuntime: true,
      imageInput: true,
      expectVisionPlan: true,
    ),
    _RouteRow(
      publicId: 'quality.blurry_image',
      internalCapability: TaskTypeMapper.blurryImage,
      handlerType: BlurryImageHandler,
      requiresOcr: false,
      requiresLlm: false,
      requiresVisionRuntime: true,
      imageInput: true,
      expectVisionPlan: true,
    ),
    _RouteRow(
      publicId: 'quality.document_image',
      internalCapability: TaskTypeMapper.documentImageQuality,
      handlerType: DocumentImageQualityHandler,
      requiresOcr: false,
      requiresLlm: false,
      requiresVisionRuntime: true,
      imageInput: true,
      expectVisionPlan: true,
    ),
    _RouteRow(
      publicId: 'catalog.duplicate_image',
      internalCapability: TaskTypeMapper.duplicateImage,
      handlerType: DuplicateImageHandler,
      requiresOcr: false,
      requiresLlm: false,
      requiresVisionRuntime: true,
      imageInput: true,
      expectVisionPlan: true,
    ),
  ];

  group('Task type route matrix', () {
    test('dispatcher exposes unique handler capabilities', () {
      final capabilities = dispatcher.capabilities.toList();
      expect(capabilities.length, capabilities.toSet().length);
      expect(capabilities.length, routes.map((r) => r.internalCapability).toSet().length);
    });

    for (final row in routes) {
      test('maps ${row.publicId} to ${row.internalCapability}', () {
        expect(TaskTypeMapper.toV1(row.publicId), row.internalCapability);
        expect(TaskTypeMapper.isPipelineTask(row.publicId), isTrue);

        expect(
          TaskTypeMapper.requiresOcr(row.internalCapability),
          row.requiresOcr,
          reason: 'OCR requirement for ${row.publicId}',
        );
        expect(
          TaskTypeMapper.requiresLlm(row.internalCapability),
          row.requiresLlm,
          reason: 'LLM requirement for ${row.publicId}',
        );
        if (row.internalCapability == TaskTypeMapper.documentExtract) {
          expect(
            TaskTypeMapper.requiresLlm(
              row.internalCapability,
              ocrOnly: true,
            ),
            isFalse,
            reason: 'ocrOnly must suppress LLM for document.extract family',
          );
        }
        if (row.requiresVisionRuntime) {
          expect(
            VisionRuntimeCatalog.isVisionCapability(row.internalCapability),
            isTrue,
            reason: 'vision runtime for ${row.publicId}',
          );
        }

        final handler = dispatcher.handlerFor(row.internalCapability);
        expect(handler, isNotNull, reason: 'missing handler for ${row.internalCapability}');
        expect(handler.runtimeType, row.handlerType);

        final backend = TaskTypeMapper.toBackend(row.internalCapability);
        if (TaskTypeMapper.backendToV1.containsKey(row.publicId)) {
          expect(backend, row.publicId);
        }

        final plan = ExecutionPlanCatalog.forTaskType(row.internalCapability);
        expect(plan.taskType, row.internalCapability);

        if (row.expectMapReducePlan) {
          expect(plan.stages.map((s) => s.operation), contains('llm_map'));
          expect(plan.stages.map((s) => s.operation), contains('llm_reduce'));
        } else if (row.expectVisionPlan) {
          expect(
            plan.stages.first.operation,
            anyOf('vlm_infer', 'vision_segment', 'vision_classify'),
          );
        }

        if (row.expectHandlerOnOcrStage) {
          final ocrStage = plan.stages.firstWhere((s) => s.operation == 'ocr');
          expect(
            ExecutionPlanCatalog.stageExecutesHandler(
              ocrStage,
              row.internalCapability,
            ),
            isTrue,
          );
        }
      });
    }

    test('rejects unknown public task types at mapper boundary', () {
      const unknown = [
        'totally.unsupported.task',
        'edge.worker.v99',
        'ocr',
        '',
        '   ',
      ];
      for (final id in unknown) {
        expect(TaskTypeMapper.toV1(id), isNull, reason: id);
        expect(TaskTypeMapper.isPipelineTask(id), isFalse, reason: id);
      }
      expect(dispatcher.handlerFor('unknown.capability.v9'), isNull);
    });

    test('catalog executable IDs route through TaskTypeMapper or are documented gaps', () {
      final catalogFile = File('../../shared/task-types/catalog.json');
      expect(catalogFile.existsSync(), isTrue, reason: catalogFile.path);
      final catalog = jsonDecode(catalogFile.readAsStringSync()) as Map<String, dynamic>;
      final categories = catalog['categories'] as List<dynamic>;
      final executableIds = <String>[];
      for (final category in categories) {
        final types = (category as Map<String, dynamic>)['types'] as List<dynamic>;
        for (final type in types) {
          final map = type as Map<String, dynamic>;
          if (map['executable'] == true) {
            executableIds.add(map['value'] as String);
          }
        }
      }

      final unmappedCatalog = <String>[];
      for (final id in executableIds) {
        if (TaskTypeMapper.toV1(id) == null) {
          unmappedCatalog.add(id);
        }
      }
      expect(
        unmappedCatalog,
        isEmpty,
        reason: 'catalog executable IDs with no worker mapper: $unmappedCatalog',
      );

      expect(
        executableIds,
        containsAll(['document.classify', 'document.summarize']),
      );
    });
  });
}
