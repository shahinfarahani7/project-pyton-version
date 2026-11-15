import '../contracts/worker_error.dart';
import 'model_selection_policy.dart';

const memoryAdmissionCodes = <String>{
  'resident_generation_exceeds_free_ram',
  'memory_budget_exceeded',
  'below_minimum_ram',
  'peak_rss_exceeds_budget',
  'resident_session_safety_floor',
  'android_low_memory',
  'memory_unknown',
  'memory_snapshot_unknown',
  'memory_snapshot_stale',
};

const engineAdmissionCodes = <String>{
  'engine_unhealthy',
  'engine_load_failure',
  'repeated_inference_crash',
  'native_oom',
  'resident_context_mismatch',
};

const thermalAdmissionCodes = <String>{
  'thermal_critical',
};

/// Turns an admission [ModelSelection] into the closed failure for that family.
///
/// Memory, engine health, and thermal are matched on [ModelSelection.reasonCodes],
/// not on the prose in [ModelSelection.reason]. A null selection means no
/// profile was published and the caller keeps the previous unconfigured path.
WorkerError? rejectionFor(ModelSelection? selection) {
  if (selection == null || selection.admitted) {
    return null;
  }
  final codes = selection.reasonCodes.toSet();
  if (codes.isEmpty && selection.reason.isNotEmpty) {
    codes.addAll(
      selection.reason.split(',').map((part) => part.trim()).where((part) => part.isNotEmpty),
    );
  }
  if (codes.intersection(memoryAdmissionCodes).isNotEmpty) {
    final budget = selection.memoryBudgetMb;
    return WorkerError(
      code: WorkerErrorCode.outOfMemoryRisk,
      message:
          'Memory budget ${budget ?? 'unknown'} MB cannot hold '
          'this generation (${codes.join(',')}).',
      retryable: true,
      stage: WorkerTaskStage.llm,
    );
  }
  if (codes.intersection(thermalAdmissionCodes).isNotEmpty) {
    return WorkerError(
      code: WorkerErrorCode.thermalBlock,
      message: 'Thermal state blocks generation (${codes.join(',')}).',
      retryable: true,
      stage: WorkerTaskStage.llm,
    );
  }
  if (codes.intersection(engineAdmissionCodes).isNotEmpty) {
    return WorkerError(
      code: WorkerErrorCode.modelNotAvailable,
      message: 'Resident engine cannot run this generation (${codes.join(',')}).',
      retryable: true,
      stage: WorkerTaskStage.llm,
    );
  }
  return WorkerError(
    code: WorkerErrorCode.modelNotAvailable,
    message: 'Generation was not admitted (${codes.join(',')}).',
    retryable: true,
    stage: WorkerTaskStage.llm,
  );
}
