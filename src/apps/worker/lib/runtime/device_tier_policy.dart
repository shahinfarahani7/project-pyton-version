enum DeviceTier { tier1, tier2, tier3 }

abstract final class DeviceTierPolicy {
  static DeviceTier fromFreeStorageMb(int freeStorageMb, {int? availableRamMb}) {
    final ram = availableRamMb ?? freeStorageMb;
    if (ram >= 8192 || freeStorageMb >= 4096) {
      return DeviceTier.tier3;
    }
    if (ram >= 6144 || freeStorageMb >= 2048) {
      return DeviceTier.tier2;
    }
    return DeviceTier.tier1;
  }

  static bool allowsCombinedOcrLlm(DeviceTier tier) {
    return tier != DeviceTier.tier1;
  }
}
