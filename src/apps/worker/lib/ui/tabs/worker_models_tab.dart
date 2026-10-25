import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/worker_model_catalog.dart';
import '../../worker_app_controller.dart';
import '../worker_theme.dart';

class WorkerModelsTab extends StatelessWidget {
  const WorkerModelsTab({
    super.key,
    required this.controller,
    required this.onDownload,
  });

  final WorkerAppController controller;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        WorkerModelCard(controller: controller, onDownload: onDownload),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: workerPanelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('OCR models', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                controller.ocrModelsReady
                    ? 'PaddleOCR assets verified on device.'
                    : 'OCR assets not detected — sideload with tools/push_paddleocr_models_to_device.ps1',
                style: const TextStyle(color: WorkerColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown on Home while the on-device model is downloading or finishing install.
class WorkerModelDownloadProgressCard extends StatelessWidget {
  const WorkerModelDownloadProgressCard({
    super.key,
    required this.controller,
  });

  final WorkerAppController controller;

  @override
  Widget build(BuildContext context) {
    final paused = controller.isGemmaDownloadPaused;
    final progress = controller.modelProgress.clamp(0.0, 1.0);
    final installing =
        !paused && controller.isGemmaDownloading && progress >= 1.0;
    final title = paused
        ? 'Paused at ${(progress * 100).toStringAsFixed(0)}%'
        : installing
        ? 'Installing model…'
        : 'Downloading ${(progress * 100).toStringAsFixed(0)}%';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: workerPanelDecoration(
        borderColor: WorkerColors.primary.withValues(alpha: 0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_download, color: WorkerColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            WorkerModelCatalog.displayName,
            style: const TextStyle(color: WorkerColors.onSurfaceVariant),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: installing ? null : progress,
                backgroundColor: WorkerColors.outlineVariant,
                color: WorkerColors.primary,
                minHeight: 8,
              ),
            ),
          ),
          if (paused || (!installing && controller.isGemmaDownloading))
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: paused
                    ? FilledButton.tonalIcon(
                        onPressed: () {
                          unawaited(controller.downloadGemmaModel());
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Resume'),
                      )
                    : OutlinedButton.icon(
                        onPressed: controller.pauseGemmaModelDownload,
                        icon: const Icon(Icons.pause),
                        label: const Text('Pause'),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class WorkerModelCard extends StatelessWidget {
  const WorkerModelCard({
    super.key,
    required this.controller,
    required this.onDownload,
  });

  final WorkerAppController controller;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final progressLabel = switch (controller.modelPhase) {
      ModelInstallPhase.idle => controller.usesDevMockInference
          ? 'Dev mock ready (x86)'
          : 'Not installed',
      ModelInstallPhase.downloading =>
        'Downloading ${(controller.modelProgress * 100).toStringAsFixed(0)}%',
      ModelInstallPhase.paused =>
        'Paused at ${(controller.modelProgress * 100).toStringAsFixed(0)}%',
      ModelInstallPhase.ready => controller.usesDevMockInference
          ? 'Dev mock ready (x86 emulator)'
          : 'Installed',
      ModelInstallPhase.failed => controller.modelError ?? 'Install failed',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: workerPanelDecoration(borderColor: WorkerColors.primary.withValues(alpha: 0.25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(progressLabel, style: Theme.of(context).textTheme.titleMedium),
          if (controller.modelPhase == ModelInstallPhase.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: controller.modelProgress,
                  backgroundColor: WorkerColors.outlineVariant,
                  color: WorkerColors.primary,
                  minHeight: 8,
                ),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: controller.canStartGemmaDownload && !controller.isGemmaReady
                  ? onDownload
                  : null,
              icon: Icon(
                controller.isGemmaReady ? Icons.check_circle : Icons.cloud_download,
              ),
              label: Text(controller.modelDownloadButtonLabel),
            ),
          ),
        ],
      ),
    );
  }
}
