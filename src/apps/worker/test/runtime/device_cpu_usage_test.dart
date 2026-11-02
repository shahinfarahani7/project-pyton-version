import 'package:edgemint_worker/runtime/device_cpu_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first sample has no rate and the next sample is busy share', () {
    final sampler = DeviceCpuUsageSampler();
    expect(sampler.sample(totalJiffies: 1000, idleJiffies: 800), isNull);
    expect(sampler.sample(totalJiffies: 1100, idleJiffies: 850), 5000);
  });

  test('a backwards counter does not invent a usage percent', () {
    final sampler = DeviceCpuUsageSampler();
    sampler.sample(totalJiffies: 1000, idleJiffies: 800);
    expect(sampler.sample(totalJiffies: 900, idleJiffies: 700), isNull);
  });
}
