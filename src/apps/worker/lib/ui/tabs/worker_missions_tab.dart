import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../worker_app_controller.dart';
import '../worker_nav_index.dart';
import '../worker_platform_icons.dart';
import '../worker_theme.dart';
import 'worker_mission_catalog.dart';
import 'worker_uptime_section.dart';

/// Missions tab — uptime progress and bonus goals.
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
        const WorkerUptimeDashboardSection(uptime: null),
        const SizedBox(height: 16),
        const Text(
          'Optional goals — progress is tracked on the server.',
          style: TextStyle(color: WorkerColors.onSurfaceVariant, height: 1.45),
        ),
        const SizedBox(height: 8),
        const Text(
          'Social steps are saved on this device until server verification is connected.',
          style: TextStyle(color: WorkerColors.dim, fontSize: 12),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < WorkerMissionCatalog.missions.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _MissionCard(
            mission: WorkerMissionCatalog.missions[i],
            controller: controller,
            onNavigate: onNavigate,
          ),
        ],
      ],
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({
    required this.mission,
    required this.controller,
    this.onNavigate,
  });

  final WorkerMissionDefinition mission;
  final WorkerAppController controller;
  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final actions = _buildMissionActions(
      mission: mission,
      controller: controller,
      onNavigate: onNavigate,
    );

    return Container(
      key: ValueKey('worker-mission-${mission.id}'),
      padding: const EdgeInsets.all(16),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MissionLeadingIcon(mission: mission),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mission.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
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
                  ],
                ),
              ),
            ],
          ),
          if (actions != null) ...[
            const SizedBox(height: 12),
            actions,
          ],
        ],
      ),
    );
  }
}

class _MissionLeadingIcon extends StatelessWidget {
  const _MissionLeadingIcon({required this.mission});

  final WorkerMissionDefinition mission;

  @override
  Widget build(BuildContext context) {
    if (WorkerPlatformIcon.isSocialKind(mission.kind)) {
      return WorkerPlatformIcon(kind: mission.kind);
    }
    return Icon(mission.icon, color: WorkerColors.primary, size: 22);
  }
}

Widget? _buildMissionActions({
  required WorkerMissionDefinition mission,
  required WorkerAppController controller,
  ValueChanged<int>? onNavigate,
}) {
  return switch (mission.kind) {
    WorkerMissionKind.socialTelegram ||
    WorkerMissionKind.socialDiscord ||
    WorkerMissionKind.socialTwitter =>
      _SocialMissionButton(mission: mission, controller: controller),
    WorkerMissionKind.dailyOnline => null,
    WorkerMissionKind.defineWallet => _DefineWalletActions(
      onNavigate: onNavigate,
    ),
  };
}

class _SocialMissionButton extends StatelessWidget {
  const _SocialMissionButton({
    required this.mission,
    required this.controller,
  });

  final WorkerMissionDefinition mission;
  final WorkerAppController controller;

  String get _actionLabel => switch (mission.kind) {
        WorkerMissionKind.socialTelegram => 'Join Telegram',
        WorkerMissionKind.socialDiscord => 'Follow Discord',
        WorkerMissionKind.socialTwitter => 'Follow Twitter',
        _ => 'Open',
      };

  @override
  Widget build(BuildContext context) {
    final completed = controller.isMissionAcknowledged(mission.id);
    final link = WorkerMissionSocialLinks.forKind(mission.kind);

    return FilledButton.tonal(
      onPressed: completed || link == null
          ? null
          : () async {
              final opened = await launchUrl(
                link,
                mode: LaunchMode.externalApplication,
              );
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
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text(
                    'Saved on this device — server verification is not connected yet.',
                  ),
                ),
              );
            },
      child: Text(
        completed
            ? 'Completed'
            : link == null
            ? 'Link not configured'
            : _actionLabel,
      ),
    );
  }
}

class _DefineWalletActions extends StatelessWidget {
  const _DefineWalletActions({this.onNavigate});

  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onNavigate == null
          ? null
          : () => onNavigate!(WorkerNavIndex.earnings),
      child: const Text('Open payout wallet setup'),
    );
  }
}
