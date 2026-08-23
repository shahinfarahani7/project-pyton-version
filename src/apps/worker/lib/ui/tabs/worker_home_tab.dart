import 'package:flutter/material.dart';

import '../../runtime/execution_status.dart';
import '../../worker_app_controller.dart';
import '../worker_theme.dart';
import '../worker_widgets.dart';

class WorkerHomeTab extends StatelessWidget {
  const WorkerHomeTab({
    super.key,
    required this.controller,
    required this.onDownloadModel,
    required this.onAvailabilityChanged,
    required this.onNavigate,
  });

  final WorkerAppController controller;
  final VoidCallback onDownloadModel;
  final ValueChanged<bool> onAvailabilityChanged;
  final ValueChanged<int> onNavigate;

  static const _demoSparkline = [0.3, 0.45, 0.4, 0.55, 0.5, 0.65, 0.72];

  String _heroSubtitle() {
    if (!controller.available) {
      return 'Turn on worker availability to receive tasks automatically.';
    }
    if (!controller.backendOnline) {
      return controller.backendMessage;
    }
    return switch (controller.executionStatus.phase) {
      ExecutionPhase.running || ExecutionPhase.preparing =>
        'Running ${controller.executionStatus.taskType ?? 'task'}…',
      ExecutionPhase.waitingForAssignment => 'Waiting for the next assignment…',
      _ => 'Tasks from the portal run automatically on this device.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final taskCount = _estimateTaskCount();
    final successRate = _successRateLabel();
    final heroSubtitle = _heroSubtitle();

    return ListView(
      padding: EdgeInsets.fromLTRB(
        wide ? 24 : 16,
        16,
        wide ? 24 : 16,
        24,
      ),
      children: [
        if (wide)
          _DesktopHeroRow(
            controller: controller,
            onDownloadModel: onDownloadModel,
            onAvailabilityChanged: onAvailabilityChanged,
            heroSubtitle: heroSubtitle,
          )
        else
          WorkerMascotHero(
            listening: controller.isAutoAssigning,
            subtitle: heroSubtitle,
          ),
        if (!wide) ...[
          const SizedBox(height: 16),
          _AvailabilityCard(
            controller: controller,
            onAvailabilityChanged: onAvailabilityChanged,
            onDownloadModel: onDownloadModel,
          ),
        ],
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 900 ? 4 : 2;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: cols == 4 ? 1.35 : 1.05,
              children: [
                WorkerKpiCard(
                  label: 'Tasks processed',
                  value: '$taskCount',
                  trend: controller.backendOnline ? 'Auto-assignment active' : 'Backend offline',
                  icon: Icons.assignment_turned_in_outlined,
                  accent: WorkerColors.primary,
                  sparkline: _demoSparkline,
                ),
                WorkerKpiCard(
                  label: 'Model status',
                  value: controller.isGemmaReady ? 'Ready' : 'Pending',
                  trend: controller.gemmaDownloadLabel,
                  icon: Icons.view_in_ar_outlined,
                  accent: WorkerColors.info,
                  trailing: controller.isGemmaReady
                      ? null
                      : TextButton(
                          onPressed: controller.canStartGemmaDownload ? onDownloadModel : null,
                          child: const Text('Prepare'),
                        ),
                ),
                WorkerKpiCard(
                  label: 'Battery',
                  value: '${controller.batteryPercent}%',
                  trend: controller.batteryLabel,
                  icon: Icons.battery_full_rounded,
                  accent: WorkerColors.success,
                  sparkline: [0.9, 0.88, 0.86, 0.85, 0.84, 0.83, controller.batteryPercent / 100],
                ),
                WorkerKpiCard(
                  label: 'Success rate',
                  value: successRate,
                  trend: 'Last run: ${controller.executionStatus.phase.name}',
                  icon: Icons.trending_up_rounded,
                  accent: WorkerColors.accentOrange,
                  sparkline: [0.92, 0.93, 0.94, 0.95, 0.96, 0.963, 0.97],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _RecentActivityPanel(controller: controller, onNavigate: onNavigate)),
              const SizedBox(width: 16),
              Expanded(child: _RequestsChartPanel(taskCount: taskCount)),
            ],
          )
        else ...[
          _RecentActivityPanel(controller: controller, onNavigate: onNavigate),
          const SizedBox(height: 16),
          _RequestsChartPanel(taskCount: taskCount),
        ],
        const SizedBox(height: 16),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _TaskMixPanel(taskCount: taskCount)),
              const SizedBox(width: 16),
              Expanded(child: _ReadinessPanel(controller: controller)),
            ],
          )
        else ...[
          _TaskMixPanel(taskCount: taskCount),
          const SizedBox(height: 16),
          _ReadinessPanel(controller: controller),
        ],
        const SizedBox(height: 16),
        _QuickActionsRow(
          controller: controller,
          onDownloadModel: onDownloadModel,
          onNavigate: onNavigate,
        ),
        const SizedBox(height: 16),
        WorkerSystemStatusBar(
          online: controller.backendOnline,
          lastSync: controller.lastSync,
        ),
      ],
    );
  }

  int _estimateTaskCount() => controller.tasksProcessed;

  String _successRateLabel() {
    return switch (controller.executionStatus.phase) {
      ExecutionPhase.completed => '100%',
      ExecutionPhase.failed => '0%',
      ExecutionPhase.running || ExecutionPhase.preparing => '—',
      _ => '96.3%',
    };
  }
}

class _DesktopHeroRow extends StatelessWidget {
  const _DesktopHeroRow({
    required this.controller,
    required this.onDownloadModel,
    required this.onAvailabilityChanged,
    required this.heroSubtitle,
  });

  final WorkerAppController controller;
  final VoidCallback onDownloadModel;
  final ValueChanged<bool> onAvailabilityChanged;
  final String heroSubtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: WorkerMascotHero(
            listening: controller.isAutoAssigning,
            subtitle: heroSubtitle,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: workerPanelDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Worker status',
                      style: TextStyle(color: WorkerColors.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    WorkerStatusChip(
                      label: controller.available && controller.backendOnline ? 'Active' : 'Idle',
                      active: controller.available && controller.backendOnline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      controller.backendMessage,
                      style: const TextStyle(color: WorkerColors.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _AvailabilityCard(
                controller: controller,
                onAvailabilityChanged: onAvailabilityChanged,
                onDownloadModel: onDownloadModel,
                compact: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({
    required this.controller,
    required this.onAvailabilityChanged,
    required this.onDownloadModel,
    this.compact = false,
  });

  final WorkerAppController controller;
  final ValueChanged<bool> onAvailabilityChanged;
  final VoidCallback onDownloadModel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: workerPanelDecoration(borderColor: WorkerColors.primary.withValues(alpha: 0.35)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ready for missions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              controller.available
                  ? 'New portal tasks start automatically while you stay Available.'
                  : 'Switch availability on to resume automatic task execution.',
              style: const TextStyle(color: WorkerColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Worker availability')),
                Switch(
                  value: controller.available,
                  onChanged: onAvailabilityChanged,
                ),
              ],
            ),
            if (!compact) ...[
              if (controller.isGemmaReady)
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: WorkerColors.success),
                    const SizedBox(width: 8),
                    Expanded(child: Text(controller.gemmaDownloadLabel)),
                  ],
                )
              else
                FilledButton.icon(
                  onPressed: controller.canStartGemmaDownload ? onDownloadModel : null,
                  icon: const Icon(Icons.download_for_offline),
                  label: Text(controller.gemmaDownloadLabel),
                ),
              if (!controller.isGemmaReady && controller.backendOnline && !controller.usesDevMockInference) ...[
                const SizedBox(height: 8),
                Text(
                  'Model not ready — on x86 MEmu use dev mock (auto), or sideload on ARM64 device.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (controller.usesDevMockInference) ...[
                const SizedBox(height: 8),
                Text(
                  'x86 emulator: dev mock OCR active. Real Qwen3 needs ARM64 phone.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentActivityPanel extends StatelessWidget {
  const _RecentActivityPanel({
    required this.controller,
    required this.onNavigate,
  });

  final WorkerAppController controller;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final entries = _recentEntries();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkerSectionHeader(
            title: 'Recent tasks',
            subtitle: 'Latest worker activity',
            action: TextButton(onPressed: () => onNavigate(1), child: const Text('View all')),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No tasks yet — create one in the customer portal and keep availability on.',
                style: TextStyle(color: WorkerColors.onSurfaceVariant),
              ),
            )
          else
            for (final entry in entries) _RecentTaskTile(entry: entry),
        ],
      ),
    );
  }

  List<_RecentEntry> _recentEntries() {
    final status = controller.executionStatus;
    if (status.taskType == null && controller.lastPortalTaskId == null) {
      return [];
    }
    return [
      _RecentEntry(
        title: status.taskType ?? 'Task',
        subtitle: controller.lastPortalTaskId ?? status.assignmentId ?? '—',
        phase: status.phase,
      ),
    ];
  }
}

class _RecentEntry {
  const _RecentEntry({
    required this.title,
    required this.subtitle,
    required this.phase,
  });

  final String title;
  final String subtitle;
  final ExecutionPhase phase;
}

class _RecentTaskTile extends StatelessWidget {
  const _RecentTaskTile({required this.entry});

  final _RecentEntry entry;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (entry.phase) {
      ExecutionPhase.completed => ('Completed', WorkerColors.success),
      ExecutionPhase.failed => ('Failed', WorkerColors.error),
      ExecutionPhase.running => ('Running', WorkerColors.info),
      ExecutionPhase.preparing => ('Preparing', WorkerColors.warning),
      _ => ('Idle', WorkerColors.onSurfaceVariant),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: WorkerColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.task_alt, color: WorkerColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(entry.subtitle, style: const TextStyle(color: WorkerColors.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
              const Text('now', style: TextStyle(color: WorkerColors.onSurfaceVariant, fontSize: 11)),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: WorkerColors.onSurfaceVariant, size: 20),
        ],
      ),
    );
  }
}

class _RequestsChartPanel extends StatelessWidget {
  const _RequestsChartPanel({required this.taskCount});

  final int taskCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WorkerSectionHeader(
            title: 'Requests over time',
            subtitle: 'Last 7 days',
          ),
          const SizedBox(height: 8),
          Text(
            '$taskCount total',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const WorkerLineChart(
            values: [120, 180, 150, 220, 190, 260, 280],
            color: WorkerColors.primary,
          ),
        ],
      ),
    );
  }
}

class _TaskMixPanel extends StatelessWidget {
  const _TaskMixPanel({required this.taskCount});

  final int taskCount;

  @override
  Widget build(BuildContext context) {
    const segments = [
      WorkerDonutSegment('LLM', 43.8, WorkerColors.primary),
      WorkerDonutSegment('OCR', 29.6, WorkerColors.info),
      WorkerDonutSegment('Vision', 15.1, WorkerColors.success),
      WorkerDonutSegment('Other', 11.5, WorkerColors.accentOrange),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WorkerSectionHeader(title: 'Tasks by type', subtitle: 'Distribution'),
          const SizedBox(height: 12),
          Row(
            children: [
              WorkerDonutChart(
                segments: segments,
                centerLabel: taskCount > 0 ? '$taskCount' : '0',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in segments)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(s.label)),
                            Text('${s.value.toStringAsFixed(1)}%'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadinessPanel extends StatelessWidget {
  const _ReadinessPanel({required this.controller});

  final WorkerAppController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Device readiness',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          WorkerReadinessRow(label: 'Battery', value: controller.batteryLabel, icon: Icons.battery_full),
          WorkerReadinessRow(label: 'Temperature', value: controller.thermalLabel, icon: Icons.thermostat),
          WorkerReadinessRow(
            label: 'Backend',
            value: controller.backendOnline ? 'Online' : 'Offline',
            icon: Icons.cloud,
          ),
          WorkerReadinessRow(label: 'Storage', value: controller.storageLabel, icon: Icons.storage),
          WorkerReadinessRow(
            label: 'Models',
            value: controller.modelPhase == ModelInstallPhase.ready ? 'Ready' : 'Pending',
            icon: Icons.view_in_ar,
          ),
          const SizedBox(height: 8),
          const WorkerLineChart(
            values: [0.94, 0.95, 0.955, 0.96, 0.962, 0.963, 0.965],
            color: WorkerColors.success,
            height: 80,
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.controller,
    required this.onDownloadModel,
    required this.onNavigate,
  });

  final WorkerAppController controller;
  final VoidCallback onDownloadModel;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        WorkerQuickAction(icon: Icons.assignment_outlined, label: 'Missions', onTap: () => onNavigate(1)),
        WorkerQuickAction(icon: Icons.view_in_ar_outlined, label: 'Models', onTap: () => onNavigate(2)),
        WorkerQuickAction(
          icon: Icons.download_for_offline,
          label: 'Prepare Qwen3',
          onTap: controller.canStartGemmaDownload && !controller.isGemmaReady ? onDownloadModel : null,
        ),
        WorkerQuickAction(icon: Icons.account_balance_wallet_outlined, label: 'Earnings', onTap: () => onNavigate(3)),
        WorkerQuickAction(icon: Icons.more_horiz, label: 'More', onTap: () => onNavigate(4)),
      ],
    );
  }
}
