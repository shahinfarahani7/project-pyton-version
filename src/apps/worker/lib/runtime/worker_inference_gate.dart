import '../contracts/worker_error.dart';

/// Blocks a new session until a requested native stop is confirmed.
///
/// [Future.timeout] does not stop LiteRT. The locked flutter_gemma_litertlm
/// 1.3.1 API is [InferenceChat.stopGeneration], which calls the lock-free
/// native `cancelGeneration`. Confirmation is the generation stream ending
/// after that call. Until then this gate stays closed.
class WorkerInferenceGate {
  WorkerInferenceGate._();

  static final WorkerInferenceGate instance = WorkerInferenceGate._();

  bool _blocked = false;
  String _reason = '';

  bool get acceptsWork => !_blocked;

  String get reason => _reason;

  void markStopUnconfirmed(String reason) {
    _blocked = true;
    _reason = reason;
  }

  void debugReset() {
    _blocked = false;
    _reason = '';
  }

  void ensureAcceptsWork() {
    if (acceptsWork) {
      return;
    }
    throw WorkerError(
      code: WorkerErrorCode.modelNotAvailable,
      message: 'Worker cannot accept work because native generation '
          'stop was not confirmed ($_reason).',
      retryable: false,
      stage: WorkerTaskStage.llm,
    );
  }
}
