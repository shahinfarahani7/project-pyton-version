import 'dart:typed_data';

import 'package:edgemint_worker/runtime/execution_plan_runner.dart';
import 'package:edgemint_worker/runtime/runtime_class_catalog.dart';
import 'package:edgemint_worker/runtime/vision_runtime_catalog.dart';
import 'package:edgemint_worker/runtime/vision_runtime_manager.dart';
import 'package:edgemint_worker/tasks/handlers/lightweight_vision_handlers.dart';
import 'package:edgemint_worker/tasks/handlers/vision_handlers.dart';
import 'package:edgemint_worker/tasks/task_type_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingVisionRuntimeManager extends VisionRuntimeManager {
  _RecordingVisionRuntimeManager({
    required this.onInferVlm,
    required this.onSegment,
    required this.onClassifyBlur,
  }) : super();

  final Future<String> Function(Uint8List imageBytes, String prompt) onInferVlm;
  final Future<Uint8List> Function(Uint8List imageBytes) onSegment;
  final Map<String, dynamic> Function(Uint8List imageBytes) onClassifyBlur;

  @override
  Future<String> inferVlm({
    required Uint8List imageBytes,
    required String prompt,
  }) =>
      onInferVlm(imageBytes, prompt);

  @override
  Future<Uint8List> segmentBackground({required Uint8List imageBytes}) =>
      onSegment(imageBytes);

  @override
  Map<String, dynamic> classifyBlur(Uint8List imageBytes) =>
      onClassifyBlur(imageBytes);
}

void main() {
  group('VisionRuntimeCatalog', () {
    test('maps capabilities to distinct Section 59 runtime classes', () {
      expect(
        VisionRuntimeCatalog.runtimeClassForCapability(
          TaskTypeMapper.visionAnalyze,
        ),
        'vlm_runtime',
      );
      expect(
        VisionRuntimeCatalog.runtimeClassForCapability(
          TaskTypeMapper.removeBackground,
        ),
        'segmentation_runtime',
      );
      expect(
        VisionRuntimeCatalog.runtimeClassForCapability('quality.blurry_image'),
        'image_classifier',
      );
    });

    test('execution plans use matching infer operations per runtime class', () {
      final vlmPlan =
          ExecutionPlanCatalog.forTaskType(TaskTypeMapper.visionAnalyze);
      expect(vlmPlan.stages.first.operation, 'vlm_infer');
      expect(vlmPlan.stages.first.runtimeClass, 'vlm_runtime');

      final segmentPlan =
          ExecutionPlanCatalog.forTaskType(TaskTypeMapper.removeBackground);
      expect(segmentPlan.stages.first.operation, 'vision_segment');
      expect(segmentPlan.stages.first.runtimeClass, 'segmentation_runtime');

      final classifyPlan =
          ExecutionPlanCatalog.forTaskType('quality.blurry_image');
      expect(classifyPlan.stages.first.operation, 'vision_classify');
      expect(classifyPlan.stages.first.runtimeClass, 'image_classifier');
    });

    test('runtime class catalog advertises distinct vision classes', () {
      final classes = RuntimeClassCatalog.fromTaskCapabilities([
        TaskTypeMapper.visionAnalyze,
        TaskTypeMapper.removeBackground,
        'quality.blurry_image',
      ]);
      expect(classes, containsAll([
        'vlm_runtime',
        'segmentation_runtime',
        'image_classifier',
      ]));
      expect(classes, isNot(contains('object_detector')));
    });
  });

  group('Vision handler routing', () {
    test('VisionAnalyzeHandler binds to VLM runtime manager', () {
      final runtime = _RecordingVisionRuntimeManager(
        onInferVlm: (_, __) async => '{}',
        onSegment: (_) async => Uint8List(0),
        onClassifyBlur: (_) => {},
      );
      final handler = VisionAnalyzeHandler(visionRuntime: runtime);

      expect(runtime.runtimeClassFor(handler.capability), 'vlm_runtime');
      expect(
        VisionRuntimeCatalog.kindFor(handler.capability),
        VisionRuntimeKind.vlm,
      );
    });

    test('RemoveBackgroundHandler binds to segmentation runtime manager', () {
      final runtime = _RecordingVisionRuntimeManager(
        onInferVlm: (_, __) async => '{}',
        onSegment: (_) async => Uint8List.fromList([1, 2, 3]),
        onClassifyBlur: (_) => {},
      );
      final handler = RemoveBackgroundHandler(visionRuntime: runtime);

      expect(runtime.runtimeClassFor(handler.capability), 'segmentation_runtime');
      expect(
        VisionRuntimeCatalog.kindFor(handler.capability),
        VisionRuntimeKind.segmentation,
      );
    });

    test('BlurryImageHandler binds to classifier runtime manager', () {
      final runtime = _RecordingVisionRuntimeManager(
        onInferVlm: (_, __) async => '{}',
        onSegment: (_) async => Uint8List(0),
        onClassifyBlur: (_) => {'blurry': false},
      );
      final handler = BlurryImageHandler(visionRuntime: runtime);

      expect(runtime.runtimeClassFor(handler.capability), 'image_classifier');
      expect(
        VisionRuntimeCatalog.kindFor(handler.capability),
        VisionRuntimeKind.classifier,
      );
    });
  });
}
