import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../worker_app_controller.dart';
import '../worker_platform_icons.dart';
import '../worker_theme.dart';
import 'worker_mission_catalog.dart';
/// Missions tab — optional bonus goals.
class WorkerMissionsTab extends StatelessWidget {
  const WorkerMissionsTab({
    super.key,
    required this.controller,
    this.onNavigate,
  });

  final WorkerAppController controller;
  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, wide ? 24 : 16, 24),
      children: [
        const Text(
          'Optional goals — progress is tracked on the server.',
          style: TextStyle(color: WorkerColors.onSurfaceVariant, height: 1.45),
        ),
        const SizedBox(height: 8),
        const Text(
          'Point amounts are estimates until server mission rewards are connected.',
          style: TextStyle(color: WorkerColors.dim, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: workerPanelDecoration(),
          child: Column(
            children: [
              for (var i = 0; i < WorkerMissionCatalog.missions.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, color: WorkerColors.outlineVariant),
                _MissionListTile(
                  mission: WorkerMissionCatalog.missions[i],
                  completed: _isMissionCompleted(
                    WorkerMissionCatalog.missions[i],
                    controller,
                  ),
                  controller: controller,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

bool _isMissionCompleted(
  WorkerMissionDefinition mission,
  WorkerAppController controller,
) {
  return switch (mission.kind) {
    WorkerMissionKind.socialTelegram ||
    WorkerMissionKind.socialDiscord ||
    WorkerMissionKind.socialTwitter =>
      controller.isMissionAcknowledged(mission.id),
    WorkerMissionKind.defineWallet => controller.payoutWallets.isNotEmpty,
    WorkerMissionKind.dailyOnline => false,
  };
}

void _showHowToComplete(
  BuildContext context, {
  required WorkerMissionDefinition mission,
  required WorkerAppController controller,
}) {
  final isSocial = WorkerPlatformIcon.isSocialKind(mission.kind);
  final socialDone = controller.isMissionAcknowledged(mission.id);

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('How to complete'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              mission.howToComplete,
              style: const TextStyle(height: 1.45),
            ),
            if (isSocial && !socialDone) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _openSocialMission(
                    dialogContext,
                    mission: mission,
                    controller: controller,
                  ),
                  child: Text(
                    WorkerMissionSocialLinks.openLabelForKind(mission.kind),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _openSocialMission(
  BuildContext context, {
  required WorkerMissionDefinition mission,
  required WorkerAppController controller,
}) async {
  final uri = WorkerMissionSocialLinks.openUriForKind(mission.kind);
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!context.mounted) {
    return;
  }
  if (!opened) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Could not open the link.')),
    );
    return;
  }
  await controller.acknowledgeMission(mission.id);
  if (!context.mounted) {
    return;
  }
  Navigator.of(context).pop();
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(
      content: Text(
        'Saved on this device — server verification is not connected yet.',
      ),
    ),
  );
}

class _MissionListTile extends StatelessWidget {
  const _MissionListTile({
    required this.mission,
    required this.completed,
    required this.controller,
  });

  final WorkerMissionDefinition mission;
  final bool completed;
  final WorkerAppController controller;

  @override
  Widget build(BuildContext context) {
    final titleTrailingIcon = _titleTrailingIcon(mission);

    return Padding(
      key: ValueKey('worker-mission-${mission.id}'),
      padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MissionCheckIndicator(
            key: ValueKey('mission-check-${mission.id}'),
            completed: completed,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              mission.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (titleTrailingIcon != null) ...[
                            const SizedBox(width: 6),
                            titleTrailingIcon,
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  mission.description,
                  style: const TextStyle(
                    color: WorkerColors.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  mission.rewardPointsLabel,
                  style: const TextStyle(
                    color: WorkerColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('mission-help-${mission.id}'),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'How to complete',
            icon: Icon(
              Icons.help_outline_rounded,
              size: 20,
              color: WorkerColors.onSurfaceVariant.withValues(alpha: 0.85),
            ),
            onPressed: () => _showHowToComplete(
              context,
              mission: mission,
              controller: controller,
            ),
          ),
        ],
      ),
    );
  }
}

Widget? _titleTrailingIcon(WorkerMissionDefinition mission) {
  if (WorkerPlatformIcon.isSocialKind(mission.kind)) {
    return WorkerPlatformIcon(kind: mission.kind, size: 22);
  }
  if (mission.kind == WorkerMissionKind.dailyOnline ||
      mission.kind == WorkerMissionKind.defineWallet) {
    return Icon(mission.icon, size: 20, color: WorkerColors.primary);
  }
  return null;
}

class _MissionCheckIndicator extends StatelessWidget {
  const _MissionCheckIndicator({super.key, required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Icon(
        completed ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
        size: 26,
        color: completed ? WorkerColors.primary : WorkerColors.dim,
      ),
    );
  }
}

