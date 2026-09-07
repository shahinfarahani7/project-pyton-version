/// Model storage layout and policy knobs (Architecture Sections 16, 54).
enum ModelStorageTier {
  permanent,
  cache,
}

class ModelStoragePolicy {
  const ModelStoragePolicy({
    this.minimumFreeStorageMb = 512,
    this.maxAiStorageMb = 2048,
    this.modelVersionRetention = 1,
  });

  final int minimumFreeStorageMb;
  final int maxAiStorageMb;
  final int modelVersionRetention;

  int get minimumFreeStorageBytes => minimumFreeStorageMb * 1024 * 1024;
  int get maxAiStorageBytes => maxAiStorageMb * 1024 * 1024;
}

class ModelCacheEntry {
  const ModelCacheEntry({
    required this.modelId,
    required this.tier,
    required this.sizeBytes,
    required this.lastUsedAt,
    this.pinned = false,
  });

  final String modelId;
  final ModelStorageTier tier;
  final int sizeBytes;
  final DateTime lastUsedAt;
  final bool pinned;

  bool get isPermanent => tier == ModelStorageTier.permanent;
}
