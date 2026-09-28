import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:edgemint_worker/inference/llm/hierarchical_summarize_pipeline.dart';
import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/inference/llm/summarize_inference_stage.dart';
import 'package:edgemint_worker/inference/llm/summarize_output_validator.dart';
import 'package:edgemint_worker/inference/llm/summarize_task_constraints.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/gemma_bootstrap.dart';
import 'package:edgemint_worker/runtime/gemma_inference_adapter.dart';
import 'package:edgemint_worker/runtime/gemma_model_runtime_manager.dart';
import 'package:edgemint_worker/runtime/inference_adapter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gemma/flutter_gemma.dart';

import 'fixtures/task_03494f44_regression.dart';

/// Shared harness for Phase 1 live semantic tests (device-native inference).
abstract final class Phase1LiveSemanticHarness {
  static const signingKey = 'phase1-live-semantic-test';

  static const liveEnabled = bool.fromEnvironment(
    'PHASE1_LIVE_INFERENCE',
    defaultValue: false,
  );

  /// Device-accessible path (e.g. `/sdcard/Edgemint/phase1/source.txt` after
  /// `adb push`). Windows host paths are not readable on Android.
  static const fullSourcePath = String.fromEnvironment(
    'PHASE1_FULL_SOURCE_PATH',
    defaultValue: '',
  );

  /// Optional bundled asset key (works on Android via [rootBundle]).
  static const fullSourceAsset = String.fromEnvironment(
    'PHASE1_FULL_SOURCE_ASSET',
    defaultValue: '',
  );

  static Future<QwenTaskProcessor> createLiveProcessor({
    void Function(String message)? log,
  }) async {
    await GemmaBootstrap.ensureInitialized();
    final runtime = GemmaModelRuntimeManager(
      preferredBackend: PreferredBackend.cpu,
    );
    final bundled = WorkerModelCatalog.bundledAssetFromEnvironment();
    if (bundled != null) {
      await WorkerModelCatalog.installBuilder().fromAsset(bundled).install();
    }
    final processor = QwenTaskProcessor(
      adapter: GemmaLiteRtInferenceAdapter(runtimeManager: runtime),
      log: log,
    );
    await processor.ensureRuntimeResident(signingKey: signingKey);
    return processor;
  }

  static HierarchicalSummarizePipeline createPipeline(
    QwenTaskProcessor processor, {
    void Function(String message)? log,
    Phase1CallTracker? tracker,
    SummarizeTaskConstraintsV1? constraints,
  }) {
    final resolvedConstraints = constraints ?? task03494f44Constraints();
    return HierarchicalSummarizePipeline(
      contextBudget: processor.contextBudget,
      log: log,
      runPromptJson: (prompt, {required inferenceStage}) async {
        tracker?.recordPrompt(prompt);
        return processor.runJsonTask(
          prompt: prompt,
          inferenceStage: inferenceStage,
          signingKey: signingKey,
          maxArrayItems: resolvedConstraints.keyPointCount ?? 4,
          labeledFallback: true,
          correctiveBudget: CorrectiveInferenceBudget(),
        );
      },
    );
  }

  static SummarizeValidationResult validateFinalOutput(
    Map<String, dynamic> summary, {
    SummarizeTaskConstraintsV1? constraints,
  }) =>
      SummarizeOutputValidator.validate(
        summary: summary,
        constraints: constraints ?? task03494f44Constraints(),
      );

  /// Loads and fingerprints full source text for L7.
  ///
  /// Returns null when no path/asset is configured. Throws when configured
  /// source is missing or fails SHA verification against the observed live
  /// task identity.
  static Future<Phase1VerifiedSource?> loadVerifiedFullSource() async {
    if (fullSourceAsset.isNotEmpty) {
      final text = await rootBundle.loadString(fullSourceAsset);
      return _verifySource(text, identity: 'asset=$fullSourceAsset');
    }
    if (fullSourcePath.isEmpty) {
      return null;
    }
    final file = File(fullSourcePath);
    if (!file.existsSync()) {
      throw Phase1SourceLoadException(
        'PHASE1_FULL_SOURCE_PATH not found on device: ${file.path}',
      );
    }
    final text = file.readAsStringSync();
    return _verifySource(text, identity: 'file=${file.path}');
  }

  static Phase1VerifiedSource _verifySource(
    String text, {
    required String identity,
  }) {
    final utf8Bytes = utf8.encode(text);
    final digest = sha256Hex(Uint8List.fromList(utf8Bytes));
    final verified = digest == task03494f44ObservedInputSha256 &&
        text.length == task03494f44ObservedInputChars;
    if (!verified) {
      throw Phase1SourceLoadException(
        'Source identity mismatch for $identity: '
        'chars=${text.length} expected=${task03494f44ObservedInputChars} '
        'sha256=$digest expected=${task03494f44ObservedInputSha256}. '
        'Do not run L7 on unverified text.',
      );
    }
    return Phase1VerifiedSource(
      text: text,
      identity: identity,
      chars: text.length,
      utf8Bytes: utf8Bytes.length,
      sha256: digest,
    );
  }

  static String flattenSummaryJson(Map<String, dynamic> summary) =>
      jsonEncode(summary).toLowerCase();

  static bool containsPendingRefundLanguage(String flattened) {
    const patterns = [
      'pending refund',
      'refund for incorrect milk in b426',
      'promised refund',
      'refund has not',
      'refund not received',
    ];
    return patterns.any(flattened.contains);
  }

  static bool respectsSubstitutionPriority(String flattened) {
    return flattened.contains('substitution') &&
        (flattened.contains('approved') ||
            flattened.contains('approval') ||
            flattened.contains('disabled'));
  }

  /// L1-only checks: facts present in [task03494f44FrozenPartials].
  static bool l1PreservesResolvedPaymentLanguage(String flattened) {
    return flattened.contains('72.40') ||
        flattened.contains(r'$6') ||
        flattened.contains('released') ||
        flattened.contains('received');
  }
}

class Phase1SourceLoadException implements Exception {
  Phase1SourceLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class Phase1VerifiedSource {
  const Phase1VerifiedSource({
    required this.text,
    required this.identity,
    required this.chars,
    required this.utf8Bytes,
    required this.sha256,
  });

  final String text;
  final String identity;
  final int chars;
  final int utf8Bytes;
  final String sha256;
}

class Phase1CallTracker {
  int mapCalls = 0;
  int intermediateReduceCalls = 0;
  int finalReduceCalls = 0;
  int correctiveCalls = 0;
  final prompts = <String>[];

  void recordPrompt(String prompt) {
    prompts.add(prompt);
    if (prompt.contains('Chunk metadata:')) {
      mapCalls += 1;
      return;
    }
    if (prompt.contains('merged intermediate summary')) {
      intermediateReduceCalls += 1;
      return;
    }
    if (prompt.contains('Combine the partial summaries into one final summary')) {
      finalReduceCalls += 1;
      return;
    }
    if (prompt.contains('Fix these validation failures')) {
      correctiveCalls += 1;
    }
  }

  int get totalModelCalls =>
      mapCalls + intermediateReduceCalls + finalReduceCalls + correctiveCalls;
}

class Phase1LiveRunReport {
  Phase1LiveRunReport({
    required this.scenario,
    required this.modelVersionId,
    required this.inputIdentity,
    required this.tracker,
    required this.durationMs,
    required this.rawPartials,
    required this.finalOutput,
    required this.passedSemanticChecks,
    required this.failedSemanticChecks,
    required this.chunkCount,
    this.instructionsIdentity,
    this.constraintsIdentity,
  });

  final String scenario;
  final String modelVersionId;
  final String inputIdentity;
  final String? instructionsIdentity;
  final String? constraintsIdentity;
  final Phase1CallTracker tracker;
  final int durationMs;
  final List<Map<String, dynamic>> rawPartials;
  final Map<String, dynamic> finalOutput;
  final List<String> passedSemanticChecks;
  final List<String> failedSemanticChecks;
  final int? chunkCount;

  @override
  String toString() {
    final buffer = StringBuffer()
      ..writeln('Phase1LiveRunReport scenario=$scenario')
      ..writeln('model=$modelVersionId input=$inputIdentity')
      ..writeln('instructions=${instructionsIdentity ?? "n/a"}')
      ..writeln('constraints=${constraintsIdentity ?? "n/a"}')
      ..writeln(
        'calls total=${tracker.totalModelCalls} '
        'map=${tracker.mapCalls} '
        'intermediateReduce=${tracker.intermediateReduceCalls} '
        'finalReduce=${tracker.finalReduceCalls} '
        'corrective=${tracker.correctiveCalls}',
      )
      ..writeln('durationMs=$durationMs chunkCount=${chunkCount ?? "n/a"}')
      ..writeln('passedSemanticChecks=$passedSemanticChecks')
      ..writeln('failedSemanticChecks=$failedSemanticChecks')
      ..writeln('finalOutput=${jsonEncode(finalOutput)}');
    return buffer.toString();
  }
}
