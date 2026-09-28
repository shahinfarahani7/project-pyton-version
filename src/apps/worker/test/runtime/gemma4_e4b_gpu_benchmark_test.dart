import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:edgemint_worker/models/worker_model_runtime_candidate.dart';
import 'package:edgemint_worker/runtime/gemma4_e4b_gpu_benchmark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Gemma4E4bGpuBenchmarkConfig', () {
    test('defaults to 2048 context, concurrency 1, bounded output', () {
      const config = Gemma4E4bGpuBenchmarkConfig();
      expect(config.contextTokens, 2048);
      expect(config.concurrency, 1);
      expect(config.maxOutputTokens, 256);
      expect(WorkerModelCatalog.benchmarkRuntimeMaxTokens, 2048);
      expect(Gemma4E4bBenchmarkMode.concurrency, 1);
    });
  });

  group('gemma4BenchmarkOutputValid', () {
    test('accepts valid JSON schema', () {
      expect(
        gemma4BenchmarkOutputValid(
          '{"summary":"ok","keyPoints":["a"],"riskLevel":"low"}',
        ),
        isTrue,
      );
    });

    test('rejects empty and malformed payloads', () {
      expect(gemma4BenchmarkOutputValid(''), isFalse);
      expect(gemma4BenchmarkOutputValid('not json'), isFalse);
      expect(
        gemma4BenchmarkOutputValid('{"summary":"","keyPoints":[],"riskLevel":"low"}'),
        isFalse,
      );
    });
  });

  group('gemma4SelectPreferredCandidateAfterBenchmark', () {
    test('retains A when G metrics missing', () {
      expect(
        gemma4SelectPreferredCandidateAfterBenchmark(a: null, g: null),
        WorkerModelRuntimeCandidateId.generalLitertLmA,
      );
    });

    test('retains A when G output invalid', () {
      final a = Gemma4E4bGpuBenchmarkRunMetrics(
        peakInferencePssKb: 1000,
        loadPssDeltaKb: 500,
        outputValid: true,
      );
      final g = Gemma4E4bGpuBenchmarkRunMetrics(
        peakInferencePssKb: 800,
        loadPssDeltaKb: 400,
        outputValid: false,
      );
      expect(
        gemma4SelectPreferredCandidateAfterBenchmark(a: a, g: g),
        WorkerModelRuntimeCandidateId.generalLitertLmA,
      );
    });

    test('selects G when peak PSS improves by at least 5%', () {
      final a = Gemma4E4bGpuBenchmarkRunMetrics(
        peakInferencePssKb: 1000,
        outputValid: true,
        modelLoadCount: 1,
        sessionLeak: false,
      );
      final g = Gemma4E4bGpuBenchmarkRunMetrics(
        peakInferencePssKb: 900,
        outputValid: true,
        modelLoadCount: 1,
        sessionLeak: false,
      );
      expect(
        gemma4SelectPreferredCandidateAfterBenchmark(a: a, g: g),
        WorkerModelRuntimeCandidateId.gpuLitertLmG,
      );
    });
  });

  group('gemma4BenchmarkPercentDelta', () {
    test('computes (G-A)/A*100', () {
      expect(gemma4BenchmarkPercentDelta(100, 90), -10.0);
    });
  });
}
