import 'package:flutter/material.dart';

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
      ModelInstallPhase.ready => controller.usesDevMockInference
          ? 'Dev mock ready (x86 emulator)'
          : 'Ready (qwen3-0.6b)',
      ModelInstallPhase.failed => controller.modelError ?? 'Install failed',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: workerPanelDecoration(borderColor: WorkerColors.primary.withValues(alpha: 0.25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Qwen3 0.6B model', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(progressLabel, style: const TextStyle(color: WorkerColors.onSurfaceVariant)),
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
              onPressed: controller.canStartGemmaDownload && !controller.isGemmaReady ? onDownload : null,
              icon: Icon(controller.isGemmaReady ? Icons.check_circle : Icons.cloud_download),
              label: Text(controller.gemmaDownloadLabel),
            ),
          ),
        ],
      ),
    );
  }
}
