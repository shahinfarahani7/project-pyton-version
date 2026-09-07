import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:edgemint_worker/runtime/device_constraints.dart';
import 'package:edgemint_worker/runtime/device_snapshot.dart';
import 'package:edgemint_worker/runtime/model_storage_policy.dart';
import 'package:edgemint_worker/runtime/runtime_exceptions.dart';
import 'package:edgemint_worker/runtime/storage_pressure_manager.dart';
import 'package:flutter_test/flutter_test.dart';

const _deviceUnderPressure = DeviceSnapshot(
  available: true,
  batteryPercent: 90,
  isCharging: true,
  thermalState: ThermalState.normal,
  network: NetworkKind.wifi,
  freeStorageMb: 400,
  withinSchedule: true,
  consentsGranted: ['terms', 'privacy', 'resource_use', 'reward_disclosure'],
);

void main() {
  test('LRU eviction reclaims cache models when storage is below minimum free', () {
    final manager = StoragePressureManager(
      policy: const ModelStoragePolicy(minimumFreeStorageMb: 512),
      clock: () => DateTime.parse('2026-09-02T12:00:00Z'),
    )..seedDefaultCatalog();

    final plan = manager.planEviction(bytesNeeded: 200 * 1024 * 1024);
    expect(plan.evictableModelIds, contains('mdv_qwen_legacy_cache'));
    expect(plan.evictableModelIds, isNot(contains(WorkerModelCatalog.modelVersionId)));
    expect(plan.reclaimedBytes, greaterThanOrEqualTo(200 * 1024 * 1024));

    manager.applyEvictionPlan(plan);
    expect(manager.canEvictModelId(WorkerModelCatalog.modelVersionId), isFalse);
  });

  test('active fence assignment blocks eviction of protected models', () {
    final manager = StoragePressureManager(
      policy: const ModelStoragePolicy(minimumFreeStorageMb: 512),
      clock: () => DateTime.parse('2026-09-02T12:00:00Z'),
    )..seedDefaultCatalog();

    manager.bindActiveAssignment(
      assignmentId: 'asg-active',
      fenceToken: 9,
      protectedModelIds: {'mdv_segmentation_cache'},
      protectedBlobRefs: {'runtime/chunk_checkpoints/asg-active/500'},
    );

    expect(manager.canEvictModelId('mdv_segmentation_cache'), isFalse);
    expect(manager.canEvictModelId('mdv_qwen_legacy_cache'), isTrue);

    final plan = manager.planEviction(bytesNeeded: 600 * 1024 * 1024);
    expect(plan.blockedModelIds, contains('mdv_segmentation_cache'));
    expect(plan.evictableModelIds, isNot(contains('mdv_segmentation_cache')));
    expect(
      () => manager.applyEvictionPlan(
        StorageEvictionPlan(
          evictableModelIds: ['mdv_segmentation_cache'],
          reclaimedBytes: 96 * 1024 * 1024,
          blockedModelIds: const [],
        ),
      ),
      throwsStateError,
    );
  });

  test('simulated storage full fails closed when reclaimable space is insufficient', () {
    final manager = StoragePressureManager(
      policy: const ModelStoragePolicy(minimumFreeStorageMb: 512),
      clock: () => DateTime.parse('2026-09-02T12:00:00Z'),
    );
    manager.registerEntry(
      ModelCacheEntry(
        modelId: 'mdv_only_cache',
        tier: ModelStorageTier.cache,
        sizeBytes: 64 * 1024 * 1024,
        lastUsedAt: DateTime.parse('2026-09-02T11:00:00Z'),
      ),
    );
    manager.bindActiveAssignment(
      assignmentId: 'asg-active',
      fenceToken: 3,
      protectedModelIds: {'mdv_only_cache'},
    );

    expect(
      () => manager.ensureHeadroomForWork(_deviceUnderPressure),
      throwsA(isA<ConstraintBlockedException>()),
    );
  });

  test('ensureHeadroomForWork evicts cache safely before starting work', () {
    final manager = StoragePressureManager(
      policy: const ModelStoragePolicy(minimumFreeStorageMb: 512),
      clock: () => DateTime.parse('2026-09-02T12:00:00Z'),
    )..seedDefaultCatalog();

    expect(
      () => manager.ensureHeadroomForWork(_deviceUnderPressure),
      returnsNormally,
    );
    expect(manager.canEvictModelId('mdv_qwen_legacy_cache'), isFalse);
  });
}
