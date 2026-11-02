/// Turns two `/proc/stat` samples into a whole-device CPU share in basis points.
class DeviceCpuUsageSampler {
  int? _totalJiffies;
  int? _idleJiffies;

  /// Returns 0–10000, or null until a second sample arrives.
  int? sample({required int? totalJiffies, required int? idleJiffies}) {
    if (totalJiffies == null || idleJiffies == null) {
      return null;
    }
    final previousTotal = _totalJiffies;
    final previousIdle = _idleJiffies;
    _totalJiffies = totalJiffies;
    _idleJiffies = idleJiffies;
    if (previousTotal == null || previousIdle == null) {
      return null;
    }
    final totalDelta = totalJiffies - previousTotal;
    final idleDelta = idleJiffies - previousIdle;
    if (totalDelta <= 0 || idleDelta < 0) {
      return null;
    }
    final busy = totalDelta - idleDelta;
    if (busy < 0) {
      return null;
    }
    final bps = (busy * 10000) ~/ totalDelta;
    if (bps < 0) {
      return 0;
    }
    if (bps > 10000) {
      return 10000;
    }
    return bps;
  }
}
