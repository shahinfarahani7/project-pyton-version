import '../runtime/vision_runtime_catalog.dart';
import 'task_type_mapper.dart';

/// When the execution-plan runner wraps handler work in [ModelRuntimeManager.withFreshSession].
abstract final class TaskExecutionPlanPolicy {
  /// Handlers that manage their own LiteRT session boundaries (e.g. [GemmaLiteRtInferenceAdapter]).
  static const selfManagedLlmSessionTypes = {
    TaskTypeMapper.textDirect,
  };

  static bool usesExecutionPlanShell({
    required String v1Type,
    required bool requiresLlm,
    required bool requiresNativeRuntime,
    required bool usesMapReduceShell,
    required bool executionPlanRunnerInjected,
  }) {
    if (selfManagedLlmSessionTypes.contains(v1Type)) {
      return false;
    }
    if (VisionRuntimeCatalog.isVisionCapability(v1Type)) {
      return true;
    }
    if (requiresLlm &&
        usesMapReduceShell &&
        (requiresNativeRuntime || executionPlanRunnerInjected)) {
      return true;
    }
    return false;
  }
}
