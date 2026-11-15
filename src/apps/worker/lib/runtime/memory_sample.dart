import 'device_snapshot.dart';

enum MemorySampleFreshness { fresh, stale, unavailable }

/// One read of device memory. [sampledAt] is when the probe returned,
/// not when a cached profile was first published.
class MemorySample {
  const MemorySample({
    required this.sampledAt,
    required this.freshness,
    this.snapshot,
    this.source = 'platform',
  });

  final DeviceSnapshot? snapshot;
  final DateTime sampledAt;
  final MemorySampleFreshness freshness;

  /// `platform`, `injected`, or `unavailable`. Not a measurement claim.
  final String source;

  factory MemorySample.measured(
    DeviceSnapshot snapshot, {
    DateTime? sampledAt,
    String source = 'platform',
  }) {
    return MemorySample(
      snapshot: snapshot,
      sampledAt: (sampledAt ?? DateTime.now()).toUtc(),
      freshness: MemorySampleFreshness.fresh,
      source: source,
    );
  }

  factory MemorySample.unavailable({DateTime? sampledAt}) {
    return MemorySample(
      sampledAt: (sampledAt ?? DateTime.now()).toUtc(),
      freshness: MemorySampleFreshness.unavailable,
      source: 'unavailable',
    );
  }
}
