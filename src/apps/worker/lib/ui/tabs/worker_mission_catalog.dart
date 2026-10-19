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
    required this.howToComplete,
    required this.rewardPointsLabel,
    required this.icon,
  });

  final String id;
  final WorkerMissionKind kind;
  final String title;
  final String description;
  final String howToComplete;
  /// Display-only until server mission rewards are connected.
  final String rewardPointsLabel;
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

  /// Build-time override via `--dart-define=FIBONAI_*_URL`, else catalog default.
  static Uri openUriForKind(WorkerMissionKind kind) {
    final configured = forKind(kind);
    if (configured != null) {
      return configured;
    }
    return switch (kind) {
      WorkerMissionKind.socialTelegram => defaultTelegram,
      WorkerMissionKind.socialDiscord => defaultDiscord,
      WorkerMissionKind.socialTwitter => defaultTwitter,
      _ => throw ArgumentError('Not a social mission kind: $kind'),
    };
  }

  static final Uri defaultTelegram = Uri.parse('https://t.me/FibonAI');
  static final Uri defaultDiscord = Uri.parse('https://discord.gg/fibonai');
  static final Uri defaultTwitter = Uri.parse('https://x.com/FibonAI');

  static String openLabelForKind(WorkerMissionKind kind) => switch (kind) {
        WorkerMissionKind.socialTelegram => 'Open Telegram',
        WorkerMissionKind.socialDiscord => 'Open Discord',
        WorkerMissionKind.socialTwitter => 'Open X',
        _ => 'Open link',
      };
}

abstract final class WorkerMissionCatalog {
  static const List<WorkerMissionDefinition> missions = [
    WorkerMissionDefinition(
      id: 'daily_online',
      kind: WorkerMissionKind.dailyOnline,
      title: 'Daily online',
      description: 'Verified uptime each day when the server tracks online time.',
      howToComplete:
          'Stay signed in with the worker running and heartbeats reaching the '
          'server. Each verified online day counts once the server confirms uptime.',
      rewardPointsLabel: '10 pts / verified day',
      icon: Icons.schedule_outlined,
    ),
    WorkerMissionDefinition(
      id: 'social_telegram',
      kind: WorkerMissionKind.socialTelegram,
      title: 'Join Telegram',
      description: 'Join the official FibonAI Telegram community.',
      howToComplete:
          'Open Telegram below, join the channel or group, then return here. '
          'Server verification will replace the on-device check when connected.',
      rewardPointsLabel: '25 pts (one-time)',
      icon: Icons.send_outlined,
    ),
    WorkerMissionDefinition(
      id: 'social_discord',
      kind: WorkerMissionKind.socialDiscord,
      title: 'Follow Discord',
      description: 'Follow FibonAI on Discord.',
      howToComplete:
          'Open Discord below, join the server, then return here. '
          'Server verification will replace the on-device check when connected.',
      rewardPointsLabel: '25 pts (one-time)',
      icon: Icons.forum_outlined,
    ),
    WorkerMissionDefinition(
      id: 'social_twitter',
      kind: WorkerMissionKind.socialTwitter,
      title: 'Follow Twitter',
      description: 'Follow FibonAI on X (Twitter).',
      howToComplete:
          'Open X below, follow FibonAI, then return here. '
          'Server verification will replace the on-device check when connected.',
      rewardPointsLabel: '25 pts (one-time)',
      icon: Icons.alternate_email,
    ),
    WorkerMissionDefinition(
      id: 'define_wallet',
      kind: WorkerMissionKind.defineWallet,
      title: 'Set up your payout wallet',
      description:
          'Add EUR payout details in Earnings. Verified when saved on the server.',
      howToComplete:
          'Open the Earnings tab → Payout wallets, add a valid payout destination, '
          'and save. Points apply after the server verifies your wallet.',
      rewardPointsLabel: '50 pts (one-time)',
      icon: Icons.account_balance_wallet_outlined,
    ),
  ];
}
