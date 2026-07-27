/// Canonical execution constraints derived from production policies.
abstract final class ExecutionPolicy {
  static const assignmentMode = 'auto';
  static const perTaskWorkerConfirmation = false;
  static const deliveryAckMeaning = 'transport_receipt_only';

  static const minimumBatteryPercent = 20;
  static const minimumStorageMb = 512;
  static const checkpointIntervalSeconds = 60;
  static const minimumProgressDeltaMilli = 100;
  static const checkpointRetentionMinutes = 60;
  static const maxMemoryMb = 2048;
  static const maxExecutionSeconds = 3600;

  static const requiredConsents = ['terms', 'privacy', 'resource_use', 'reward_disclosure'];
  static const resourceControls = ['availability', 'network', 'charging', 'battery', 'schedule'];

  static const goldenTaskTypes = [
    'document.ocr',
    'document.extract',
    'audio.transcribe',
  ];
}
