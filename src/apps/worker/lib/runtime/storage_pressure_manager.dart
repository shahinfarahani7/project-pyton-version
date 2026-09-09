import '../models/worker_model_catalog.dart';
import 'device_constraints.dart';
import 'device_snapshot.dart';
import 'model_storage_policy.dart';
import 'runtime_exceptions.dart';

class ActiveAssignmentStorageLease {
  const ActiveAssignmentStorageLease({
    required this.assignmentId,
    required this.fenceToken,
    required this.protectedModelIds,
    required this.protectedBlobRefs,
  });

  final String assignmentId;
  final int fenceToken;
  final Set<String> protectedModelIds;
  final Set<String> protectedBlobRefs;
}

class StoragePressureEvaluation {
  const StoragePressureEvaluation({
    required this.pressureActive,
    required this.freeStorageBytes,
    required this.minimumFreeBytes,
    required this.reclaimableBytes,
  });

  final bool pressureActive;
  final int freeStorageBytes;
  final int minimumFreeBytes;
  final int reclaimableBytes;
}

class StorageEvictionPlan {
  const StorageEvictionPlan({
    required this.evictableModelIds,
    required this.reclaimedBytes,
    required this.blockedModelIds,
  });

  final List<String> evictableModelIds;
  final int reclaimedBytes;
  final List<String> blockedModelIds;
}

/// LRU cache eviction under storage pressure; active fence assignments are protected.
class StoragePressureManager {
  StoragePressureManager({
    ModelStoragePolicy policy = const ModelStoragePolicy(),
    DateTime Function()? clock,
  })  : _policy = policy,
        _clock = clock ?? DateTime.now;

  final ModelStoragePolicy _policy;
  final DateTime Function() _clock;
  final List<ModelCacheEntry> _entries = [];
  ActiveAssignmentStorageLease? _activeLease;

  ActiveAssignmentStorageLease? get activeLease => _activeLease;

  void registerEntry(ModelCacheEntry entry) {
    _entries.removeWhere((existing) => existing.modelId == entry.modelId);
    _entries.add(entry);
  }

  void touchModel(String modelId) {
    final index = _entries.indexWhere((entry) => entry.modelId == modelId);
    if (index == -1) {
      return;
    }
    final existing = _entries[index];
    _entries[index] = ModelCacheEntry(
      modelId: existing.modelId,
      tier: existing.tier,
      sizeBytes: existing.sizeBytes,
      lastUsedAt: _clock(),
      pinned: existing.pinned,
    );
  }

  void seedDefaultCatalog() {
    registerEntry(
      ModelCacheEntry(
        modelId: WorkerModelCatalog.modelVersionId,
        tier: ModelStorageTier.permanent,
        sizeBytes: 547 * 1024 * 1024,
        lastUsedAt: _clock(),
        pinned: true,
      ),
    );
    registerEntry(
      ModelCacheEntry(
        modelId: 'mdv_paddleocr_mobile',
        tier: ModelStorageTier.permanent,
        sizeBytes: 48 * 1024 * 1024,
        lastUsedAt: _clock(),
        pinned: true,
      ),
    );
    registerEntry(
      ModelCacheEntry(
        modelId: 'mdv_qwen_legacy_cache',
        tier: ModelStorageTier.cache,
        sizeBytes: 520 * 1024 * 1024,
        lastUsedAt: _clock().subtract(const Duration(days: 14)),
      ),
    );
    registerEntry(
      ModelCacheEntry(
        modelId: 'mdv_segmentation_cache',
        tier: ModelStorageTier.cache,
        sizeBytes: 96 * 1024 * 1024,
        lastUsedAt: _clock().subtract(const Duration(days: 3)),
      ),
    );
  }

  void bindActiveAssignment({
    required String assignmentId,
    required int fenceToken,
    required Set<String> protectedModelIds,
    Iterable<String> protectedBlobRefs = const [],
  }) {
    _activeLease = ActiveAssignmentStorageLease(
      assignmentId: assignmentId,
      fenceToken: fenceToken,
      protectedModelIds: protectedModelIds,
      protectedBlobRefs: protectedBlobRefs.toSet(),
    );
    for (final modelId in protectedModelIds) {
      touchModel(modelId);
    }
  }

  void clearActiveAssignment() {
    _activeLease = null;
  }

  StoragePressureEvaluation evaluateDevice(DeviceSnapshot device) {
    final freeBytes = device.freeStorageMb * 1024 * 1024;
    return evaluateFreeBytes(freeBytes);
  }

  StoragePressureEvaluation evaluateFreeBytes(int freeStorageBytes) {
    final reclaimable = _entries
        .where(canEvictModel)
        .fold<int>(0, (total, entry) => total + entry.sizeBytes);
    return StoragePressureEvaluation(
      pressureActive: freeStorageBytes < _policy.minimumFreeStorageBytes,
      freeStorageBytes: freeStorageBytes,
      minimumFreeBytes: _policy.minimumFreeStorageBytes,
      reclaimableBytes: reclaimable,
    );
  }

  bool canEvictModel(ModelCacheEntry entry) => canEvictModelId(entry.modelId);

  bool canEvictModelId(String modelId) {
    final entry = _entries.firstWhere(
      (candidate) => candidate.modelId == modelId,
     orElse: () => ModelCacheEntry(
       modelId: '',
       tier: ModelStorageTier.permanent,
       sizeBytes: 0,
       lastUsedAt: _epoch,
       pinned: true,
     ),
    );
    if (entry.modelId.isEmpty) {
      return false;
    }
    if (entry.pinned || entry.isPermanent) {
      return false;
    }
    final lease = _activeLease;
    if (lease != null && lease.protectedModelIds.contains(modelId)) {
      return false;
    }
    return entry.tier == ModelStorageTier.cache;
  }

  StorageEvictionPlan planEviction({required int bytesNeeded}) {
    final blocked = <String>[];
    final evictable = <ModelCacheEntry>[];
    for (final entry in _entries) {
      if (entry.tier != ModelStorageTier.cache) {
        continue;
      }
      if (canEvictModel(entry)) {
        evictable.add(entry);
      } else {
        blocked.add(entry.modelId);
      }
    }
    evictable.sort((left, right) => left.lastUsedAt.compareTo(right.lastUsedAt));

    final selected = <String>[];
    var reclaimed = 0;
    for (final entry in evictable) {
      if (reclaimed >= bytesNeeded) {
        break;
      }
      selected.add(entry.modelId);
      reclaimed += entry.sizeBytes;
    }

    return StorageEvictionPlan(
      evictableModelIds: selected,
      reclaimedBytes: reclaimed,
      blockedModelIds: blocked,
    );
  }

  void applyEvictionPlan(StorageEvictionPlan plan) {
    for (final modelId in plan.evictableModelIds) {
      if (!canEvictModelId(modelId)) {
        throw StateError('Refusing to evict protected model $modelId');
      }
    }
    _entries.removeWhere((entry) => plan.evictableModelIds.contains(entry.modelId));
  }

  void ensureHeadroomForWork(DeviceSnapshot device) {
    final evaluation = evaluateDevice(device);
    if (!evaluation.pressureActive) {
      return;
    }

    final deficit = evaluation.minimumFreeBytes - evaluation.freeStorageBytes;
    final plan = planEviction(bytesNeeded: deficit);
    if (plan.reclaimedBytes < deficit) {
      throw ConstraintBlockedException(
        ConstraintViolation.storageLow,
        'storage pressure: need ${deficit ~/ (1024 * 1024)} MB, '
        'reclaimable ${plan.reclaimedBytes ~/ (1024 * 1024)} MB',
      );
    }
    applyEvictionPlan(plan);
  }

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);
}
