import 'execution_policy.dart';

class SandboxLimits {
  const SandboxLimits({
    this.maxMemoryMb = ExecutionPolicy.maxMemoryMb,
    this.maxExecutionSeconds = ExecutionPolicy.maxExecutionSeconds,
  });

  final int maxMemoryMb;
  final int maxExecutionSeconds;

  bool withinMemory(int observedMb) => observedMb <= maxMemoryMb;

  bool withinDuration(Duration elapsed) => elapsed.inSeconds <= maxExecutionSeconds;
}
