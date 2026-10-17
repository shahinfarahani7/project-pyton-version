import 'package:flutter/material.dart';

/// Known worker mission kinds (display catalog; verification is server-side).
enum WorkerMissionKind {
  dailyOnline,
  socialTelegram,
  socialDiscord,
  socialTwitter,
  defineWallet,
}

/// Static mission definition for the Missions tab.
class WorkerMissionDefinition {
  const WorkerMissionDefinition({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String id;
  final WorkerMissionKind kind;
  final String title;
  final String description;
  final IconData icon;
}

abstract final class WorkerMissionSocialLinks {
  static Uri? _fromEnv(String key) {
    final raw = String.fromEnvironment(key);
    if (raw.isEmpty) {
      return null;
    }
    return Uri.tryParse(raw);
  }

  static Uri? get telegram => _fromEnv('FIBONAI_TELEGRAM_URL');

  static Uri? get discord => _fromEnv('FIBONAI_DISCORD_URL');

  static Uri? get twitter => _fromEnv('FIBONAI_TWITTER_URL');

  static Uri? forKind(WorkerMissionKind kind) => switch (kind) {
        WorkerMissionKind.socialTelegram => telegram,
        WorkerMissionKind.socialDiscord => discord,
        WorkerMissionKind.socialTwitter => twitter,
        _ => null,
      };
}

abstract final class WorkerMissionCatalog {
  static const List<WorkerMissionDefinition> missions = [
    WorkerMissionDefinition(
      id: 'daily_online',
      kind: WorkerMissionKind.dailyOnline,
      title: 'Daily online',
      description: 'Verified uptime each day. Progress is shown above.',
      icon: Icons.schedule_outlined,
    ),
    WorkerMissionDefinition(
      id: 'social_telegram',
      kind: WorkerMissionKind.socialTelegram,
      title: 'Join Telegram',
      description: 'Join the official FibonAI Telegram community.',
      icon: Icons.send_outlined,
    ),
    WorkerMissionDefinition(
      id: 'social_discord',
      kind: WorkerMissionKind.socialDiscord,
      title: 'Follow Discord',
      description: 'Follow FibonAI on Discord.',
      icon: Icons.forum_outlined,
    ),
    WorkerMissionDefinition(
      id: 'social_twitter',
      kind: WorkerMissionKind.socialTwitter,
      title: 'Follow Twitter',
      description: 'Follow FibonAI on X (Twitter).',
      icon: Icons.alternate_email,
    ),
    WorkerMissionDefinition(
      id: 'define_wallet',
      kind: WorkerMissionKind.defineWallet,
      title: 'Set up your payout wallet',
      description:
          'Add EUR payout details in Earnings. Verified when saved on the server.',
      icon: Icons.account_balance_wallet_outlined,
    ),
  ];
}
