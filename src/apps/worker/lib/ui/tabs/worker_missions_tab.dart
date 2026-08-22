import 'package:flutter/material.dart';

import '../../worker_app_controller.dart';
import '../worker_theme.dart';
import '../worker_widgets.dart';

class WorkerMissionsTab extends StatelessWidget {
  const WorkerMissionsTab({
    super.key,
    required this.controller,
  });

  final WorkerAppController controller;

  @override
  Widget build(BuildContext context) {
    final phase = controller.executionStatus.phase;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: workerPanelDecoration(borderColor: WorkerColors.primary.withValues(alpha: 0.3)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Task queue', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                controller.backendOnline
                    ? '1. Create a task in the customer portal (Tasks → New Task)\n'
                      '2. Keep worker availability ON — assignments start automatically\n'
                      '3. Install Qwen3 on ARM64 for real on-device inference'
                    : 'Backend offline — run: adb reverse tcp:8081 tcp:8081',
                style: const TextStyle(color: WorkerColors.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 16),
              _GatewayTile(
                online: controller.backendOnline,
                message: controller.backendMessage,
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _StatusTile(
                      icon: Icons.assignment,
                      title: 'Auto-assignment',
                      subtitle: controller.isAutoAssigning
                          ? 'Listening for new tasks'
                          : 'Paused — turn availability on',
                    ),
                  ),
                  WorkerStatusChip(
                    label: controller.isAutoAssigning ? 'Active' : 'Paused',
                    active: controller.isAutoAssigning,
                  ),
                ],
              ),
              const Divider(height: 24),
              _StatusTile(
                icon: Icons.play_circle_outline,
                title: 'Last run status',
                subtitle: phase.name +
                    (controller.executionStatus.taskType != null
                        ? ' · ${controller.executionStatus.taskType}'
                        : '') +
                    (controller.lastPortalTaskId != null
                        ? '\nTask: ${controller.lastPortalTaskId}'
                        : ''),
              ),
              if (controller.backendOnline && !controller.isGemmaReady) ...[
                const SizedBox(height: 12),
                Text(
                  'Tasks still arrive automatically. Install Qwen3 (Models tab) for real inference on ARM64.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: WorkerColors.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (controller.executionStatus.detail != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: workerPanelDecoration(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.smart_toy_outlined, color: WorkerColors.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Last result', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      SelectableText(
                        controller.executionStatus.detail!,
                        style: const TextStyle(color: WorkerColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _GatewayTile extends StatelessWidget {
  const _GatewayTile({required this.online, required this.message});

  final bool online;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          online ? Icons.cloud_done : Icons.cloud_off,
          color: online ? WorkerColors.success : WorkerColors.warning,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Worker gateway', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(message, style: const TextStyle(color: WorkerColors.onSurfaceVariant)),
            ],
          ),
        ),
        WorkerStatusChip(label: online ? 'Online' : 'Offline', active: online),
      ],
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: WorkerColors.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: WorkerColors.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
