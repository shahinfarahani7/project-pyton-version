import 'dart:async';

import 'package:flutter/material.dart';

import '../../runtime/execution_status.dart';
import '../../runtime/worker_app_update.dart';
import '../../runtime/worker_fibonai_earnings.dart';
import '../../worker_app_controller.dart';
import '../worker_mascot.dart';
import '../worker_theme.dart';
import '../worker_widgets.dart';
import 'worker_models_tab.dart';

class WorkerHomeTab extends StatefulWidget {
  const WorkerHomeTab({
    super.key,
    required this.controller,
  });

  final WorkerAppController controller;

  @override
  State<WorkerHomeTab> createState() => _WorkerHomeTabState();
}

class _WorkerHomeTabState extends State<WorkerHomeTab> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final locked = controller.blocksAppUntilUpdate;
        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, wide ? 24 : 16, 24),
          children: [
            if (controller.showsAppUpdateCard)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _AppUpdateCard(controller: controller),
              ),
            if (!locked && controller.showsModelUpdateCard)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _ModelUpdateCard(controller: controller),
              ),
            if (controller.showsModelDownloadProgressCard)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: WorkerModelDownloadProgressCard(controller: controller),
              ),
            if (!locked) ...[
              _WorkerCharacter(
                working: mascotIsWorking(controller.executionStatus.phase),
              ),
              const SizedBox(height: 16),
              _HomeStatRow(
                tasksCompleted: controller.tasksProcessed,
                fibonaiAtomic: controller.fibonaiBalanceFromServer
                    ? controller.fibonaiBalanceAtomic
                    : controller.tasksProcessed *
                          fibonaiPointsPerCompletedTask,
              ),
              const SizedBox(height: 16),
              _EarningsChart(values: controller.fibonaiDailyPoints),
            ],
          ],
        );
      },
    );
  }
}

class _WorkerCharacter extends StatelessWidget {
  const _WorkerCharacter({required this.working});

  final bool working;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 220,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: workerPanelDecoration(),
      child: WorkerMascotAnimation(working: working, height: 196),
    );
  }
}

class _HomeStatRow extends StatelessWidget {
  const _HomeStatRow({required this.tasksCompleted, required this.fibonaiAtomic});

  final int tasksCompleted;
  final int fibonaiAtomic;

  @override
  Widget build(BuildContext context) {
    final fibonaiTotal = fibonaiAtomic;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              label: 'Tasks completed',
              value: '$tasksCompleted',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'Fibonai',
              value: formatFibonaiAtomic(fibonaiTotal),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WorkerColors.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: WorkerColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningsChart extends StatelessWidget {
  const _EarningsChart({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final earned = values.fold<double>(0, (sum, value) => sum + value);
    final hasEarnings = earned > 0;
    final summary = hasEarnings
        ? '${earned.round()} Fibonai over the last 7 days. '
            'Rewards are variable and are not guaranteed.'
        : 'No Fibonai earned in the last 7 days. '
            'Rewards are variable and are not guaranteed.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Earnings',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            style: const TextStyle(
              color: WorkerColors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          WorkerLineChart(
            values: values,
            color: WorkerColors.primary,
          ),
        ],
      ),
    );
  }
}

class _AppUpdateCard extends StatelessWidget {
  const _AppUpdateCard({required this.controller});

  final WorkerAppController controller;

  @override
  Widget build(BuildContext context) {
    final phase = controller.appUpdatePhase;
    final busy =
        phase == WorkerAppUpdatePhase.downloading ||
        phase == WorkerAppUpdatePhase.installing;
    final title = switch (phase) {
      WorkerAppUpdatePhase.downloading =>
        'Downloading update ${(controller.appUpdateProgress * 100).toStringAsFixed(0)}%',
      WorkerAppUpdatePhase.installing => controller.appUpdateFromPlay
          ? 'Opening Google Play…'
          : 'Opening installer…',
      WorkerAppUpdatePhase.failed => 'App update failed',
      WorkerAppUpdatePhase.available ||
      WorkerAppUpdatePhase.idle =>
        controller.appUpdateMandatory ? 'Required app update' : 'App update',
    };
    final actionLabel = phase == WorkerAppUpdatePhase.failed
        ? 'Try again'
        : controller.appUpdateFromPlay
        ? 'Update with Google Play'
        : 'Update app';

    return Semantics(
      container: true,
      label: 'Application update',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: workerPanelDecoration(
          borderColor: WorkerColors.primary.withValues(alpha: 0.25),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update_alt, color: WorkerColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (controller.appUpdateFromPlay) ...[
              const SizedBox(height: 8),
              const Text(
                'Google Play',
                style: TextStyle(color: WorkerColors.onSurfaceVariant),
              ),
            ] else if (controller.appUpdateVersionName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Version ${controller.appUpdateVersionName}',
                style: const TextStyle(color: WorkerColors.onSurfaceVariant),
              ),
            ],
            if (controller.appUpdateMandatory &&
                phase != WorkerAppUpdatePhase.downloading &&
                phase != WorkerAppUpdatePhase.installing) ...[
              const SizedBox(height: 8),
              const Text(
                'Install this update to continue.',
                style: TextStyle(color: WorkerColors.onSurfaceVariant),
              ),
            ],
            if (controller.appUpdateNotes != null &&
                phase != WorkerAppUpdatePhase.downloading &&
                phase != WorkerAppUpdatePhase.installing) ...[
              const SizedBox(height: 8),
              Text(
                controller.appUpdateNotes!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: WorkerColors.onSurfaceVariant),
              ),
            ],
            if (controller.appUpdateError != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.appUpdateError!,
                style: const TextStyle(color: WorkerColors.error),
              ),
            ],
            if (controller.appUpdateNotice != null &&
                controller.appUpdateError == null) ...[
              const SizedBox(height: 8),
              Text(
                controller.appUpdateNotice!,
                style: const TextStyle(color: WorkerColors.onSurfaceVariant),
              ),
            ],
            if (busy)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: phase == WorkerAppUpdatePhase.installing
                        ? null
                        : controller.appUpdateProgress.clamp(0.0, 1.0),
                    backgroundColor: WorkerColors.outlineVariant,
                    color: WorkerColors.primary,
                    minHeight: 8,
                  ),
                ),
              ),
            if (!busy)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () {
                      unawaited(controller.installOfferedAppUpdate());
                    },
                    child: Text(actionLabel),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModelUpdateCard extends StatelessWidget {
  const _ModelUpdateCard({required this.controller});

  final WorkerAppController controller;

  @override
  Widget build(BuildContext context) {
    final failed = controller.modelUpdatePhase == WorkerAppUpdatePhase.failed;
    final title = failed ? 'Update failed' : 'Update required';
    return Semantics(
      container: true,
      label: 'Required update',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: workerPanelDecoration(
          borderColor: WorkerColors.primary.withValues(alpha: 0.25),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download_rounded, color: WorkerColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (controller.modelUpdateError != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.modelUpdateError!,
                style: const TextStyle(color: WorkerColors.error),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    unawaited(controller.installOfferedModelUpdate());
                  },
                  child: Text(failed ? 'Try again' : 'Update'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

