import 'dart:convert';

import 'package:edgemint_worker/inference/llm/summarize_output_normalizer.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/inference/llm/fixtures/task_03494f44_frozen_partials.dart';
import '../test/inference/llm/fixtures/task_03494f44_regression.dart';
import '../test/inference/llm/phase1_live_semantic_harness.dart';

/// Live Phase 1 semantic acceptance (device-native Qwen2.5 1.5B).
///
/// Frozen-partials reduce-only (L1):
/// ```powershell
/// cd src\apps\worker
/// $env:NO_PROXY="127.0.0.1,localhost"
/// . ..\..\..\tools\flutter_env.ps1
/// flutter test integration_test/phase1_live_semantic_test.dart -d emulator-5554 `
///   --use-application-binary=..\..\..\artifacts\worker-installed-debug.apk `
///   --plain-name "L1 frozen partials" `
///   --dart-define=PHASE1_LIVE_INFERENCE=true `
///   --dart-define=WORKER_USE_BACKEND_ARTIFACT=false `
///   --dart-define=WORKER_VERBOSE_TASK_CONTENT=true `
///   --dart-define=EDGEMINT_WORKER_BASE_URL=http://172.20.34.71:8081
/// ```
///
/// Full-source map/reduce (L7) requires verified source on the device:
/// ```powershell
/// adb push C:\path\to\verified-source.txt /sdcard/Edgemint/phase1/source.txt
/// flutter test integration_test/phase1_live_semantic_test.dart -d emulator-5554 `
///   --use-application-binary=..\..\..\artifacts\worker-installed-debug.apk `
///   --plain-name "L7 full-source" `
///   --dart-define=PHASE1_LIVE_INFERENCE=true `
///   --dart-define=PHASE1_FULL_SOURCE_PATH=/sdcard/Edgemint/phase1/source.txt `
///   ...
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final constraints = task03494f44Constraints();
  const instructions = task03494f44Instructions;

  group('Phase 1 live semantic acceptance', () {
    test('L1 frozen partials — final reduce only', () async {
      if (!Phase1LiveSemanticHarness.liveEnabled) {
        return;
      }

      final logs = <String>[];
      final tracker = Phase1CallTracker();
      final stopwatch = Stopwatch()..start();
      final processor = await Phase1LiveSemanticHarness.createLiveProcessor(
        log: logs.add,
      );
      final pipeline = Phase1LiveSemanticHarness.createPipeline(
        processor,
        log: logs.add,
        tracker: tracker,
        constraints: constraints,
      );

      final partials = task03494f44FrozenPartials();
      final result = await pipeline.reduceLegacyPartials(
        partials,
        userInstructions: instructions,
        constraints: constraints,
      );
      stopwatch.stop();

      final normalized = SummarizeOutputNormalizer.normalize(result);
      final finalOutput = Map<String, dynamic>.from(normalized.normalized);
      final structural = Phase1LiveSemanticHarness.validateFinalOutput(
        finalOutput,
        constraints: constraints,
      );
      final flattened = Phase1LiveSemanticHarness.flattenSummaryJson(finalOutput);

      final passed = <String>[];
      final failed = <String>[];

      if (structural.passed) {
        passed.add('structural_final_contract');
      } else {
        failed.add(
          'structural_final_contract:${structural.blockingViolations.join(";")}',
        );
      }

      if (!Phase1LiveSemanticHarness.containsPendingRefundLanguage(flattened)) {
        passed.add('no_pending_refund_language');
      } else {
        failed.add('no_pending_refund_language');
      }

      if (Phase1LiveSemanticHarness.respectsSubstitutionPriority(flattened)) {
        passed.add('substitution_priority_in_output');
      } else {
        failed.add('substitution_priority_in_output');
      }

      if (Phase1LiveSemanticHarness.l1PreservesResolvedPaymentLanguage(
        flattened,
      )) {
        passed.add('resolved_payment_language_from_partials');
      } else {
        failed.add('resolved_payment_language_from_partials');
      }

      if (tracker.mapCalls == 0 && tracker.finalReduceCalls >= 1) {
        passed.add('reduce_only_entry_point');
      } else {
        failed.add(
          'reduce_only_entry_point:map=${tracker.mapCalls} '
          'finalReduce=${tracker.finalReduceCalls}',
        );
      }

      final report = Phase1LiveRunReport(
        scenario: 'L1_frozen_partials_reduce_only',
        modelVersionId: WorkerModelCatalog.modelVersionId,
        inputIdentity:
            'frozen_partials semantic_reconstruction map1=${task03494f44Map1Provenance.name} '
            'map2=${task03494f44Map2Provenance.name}',
        instructionsIdentity: 'task03494f44Instructions (100w/4kp live task)',
        constraintsIdentity: jsonEncode(constraints.toJson()),
        tracker: tracker,
        durationMs: stopwatch.elapsedMilliseconds,
        rawPartials: partials,
        finalOutput: finalOutput,
        passedSemanticChecks: passed,
        failedSemanticChecks: failed,
        chunkCount: null,
      );

      // ignore: avoid_print
      print(report);
      for (final line in logs.where((entry) => entry.startsWith('[CHUNK REDUCE'))) {
        // ignore: avoid_print
        print(line);
      }

      expect(failed, isEmpty, reason: report.toString());
    }, skip: Phase1LiveSemanticHarness.liveEnabled
        ? false
        : 'Set --dart-define=PHASE1_LIVE_INFERENCE=true and run on a device with Qwen2.5 1.5B installed');

    test('L7 full-source map/reduce', () async {
      if (!Phase1LiveSemanticHarness.liveEnabled) {
        return;
      }

      Phase1VerifiedSource source;
      try {
        final loaded = await Phase1LiveSemanticHarness.loadVerifiedFullSource();
        if (loaded == null) {
          fail(
            'Verified source unavailable. Push the original 13,769-char source to '
            'the device and set '
            '--dart-define=PHASE1_FULL_SOURCE_PATH=/sdcard/Edgemint/phase1/source.txt '
            '(expected sha256=${task03494f44ObservedInputSha256}). '
            'Transcript reconstruction does not match and must not be substituted.',
          );
        }
        source = loaded;
      } on Phase1SourceLoadException catch (error) {
        fail(error.message);
      }

      final logs = <String>[];
      final tracker = Phase1CallTracker();
      final stopwatch = Stopwatch()..start();
      final processor = await Phase1LiveSemanticHarness.createLiveProcessor(
        log: logs.add,
      );
      final pipeline = Phase1LiveSemanticHarness.createPipeline(
        processor,
        log: logs.add,
        tracker: tracker,
        constraints: constraints,
      );

      final plan = processor.planInputChunks(
        source.text,
        reservedPromptTokens: processor.summarizePromptReserveTokens(
          userInstructions: instructions,
          constraints: constraints,
        ),
      );

      final result = await pipeline.summarize(
        inputText: source.text,
        plan: plan,
        userInstructions: instructions,
        constraints: constraints,
      );
      stopwatch.stop();

      final normalized = SummarizeOutputNormalizer.normalize(result);
      final finalOutput = Map<String, dynamic>.from(normalized.normalized);
      final structural = Phase1LiveSemanticHarness.validateFinalOutput(
        finalOutput,
        constraints: constraints,
      );
      final flattened = Phase1LiveSemanticHarness.flattenSummaryJson(finalOutput);

      final passed = <String>[];
      final failed = <String>[];

      if (structural.passed) {
        passed.add('structural_final_contract');
      } else {
        failed.add(
          'structural_final_contract:${structural.blockingViolations.join(";")}',
        );
      }

      void requireContains(String id, String needle) {
        if (flattened.contains(needle.toLowerCase())) {
          passed.add(id);
        } else {
          failed.add(id);
        }
      }

      requireContains('b410_late', 'b410');
      requireContains('b426_substitution', 'b426');
      requireContains('coupon_declined', 'coupon');
      requireContains('coupon_minimum', '50');
      requireContains('payment_amount', '72.40');
      requireContains('refund_received', r'$6');

      if (!Phase1LiveSemanticHarness.containsPendingRefundLanguage(flattened)) {
        passed.add('no_pending_refund_language');
      } else {
        failed.add('no_pending_refund_language');
      }

      if (Phase1LiveSemanticHarness.respectsSubstitutionPriority(flattened)) {
        passed.add('substitution_priority_in_output');
      } else {
        failed.add('substitution_priority_in_output');
      }

      final report = Phase1LiveRunReport(
        scenario: 'L7_full_source',
        modelVersionId: WorkerModelCatalog.modelVersionId,
        inputIdentity:
            '${source.identity} chars=${source.chars} utf8Bytes=${source.utf8Bytes} sha256=${source.sha256}',
        instructionsIdentity: 'task03494f44Instructions (100w/4kp live task)',
        constraintsIdentity: jsonEncode(constraints.toJson()),
        tracker: tracker,
        durationMs: stopwatch.elapsedMilliseconds,
        rawPartials: const [],
        finalOutput: finalOutput,
        passedSemanticChecks: passed,
        failedSemanticChecks: failed,
        chunkCount: plan.totalChunks,
      );

      // ignore: avoid_print
      print(report);
      // ignore: avoid_print
      print('sourceVerified=${source.identity} chunks=${plan.totalChunks}');
      // ignore: avoid_print
      print('finalOutput=${jsonEncode(finalOutput)}');

      expect(failed, isEmpty, reason: report.toString());
    }, skip: Phase1LiveSemanticHarness.liveEnabled
        ? false
        : 'Set --dart-define=PHASE1_LIVE_INFERENCE=true for full-source live acceptance');
  });
}
