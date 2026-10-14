import 'package:flutter/material.dart';

import '../../api/worker_contribution_models.dart';
import '../worker_theme.dart';

/// Contributor level, XP progress and Boost status on the home dashboard.
class WorkerContributionSection extends StatelessWidget {
  const WorkerContributionSection({
    super.key,
    required this.summary,
    required this.loading,
    required this.error,
    required this.activating,
    required this.onRetry,
    required this.onActivateBoost,
  });

  final WorkerContributionSummary? summary;
  final bool loading;
  final String? error;
  final bool activating;
  final VoidCallback onRetry;

  /// Returns null on success, otherwise a problem code.
  final Future<String?> Function() onActivateBoost;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: workerPanelDecoration(),
      child: data == null ? _placeholder(context) : _content(context, data),
    );
  }

  Widget _placeholder(BuildContext context) {
    if (loading) {
      return const Row(
        children: [
          SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Loading contribution level…', style: TextStyle(color: WorkerColors.onSurfaceVariant)),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            error == null
                ? 'Contribution level is not loaded yet.'
                : contributionLoadErrorMessage(error),
            style: const TextStyle(color: WorkerColors.onSurfaceVariant, fontSize: 13),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }

  Widget _content(BuildContext context, WorkerContributionSummary data) {
    final theme = Theme.of(context);
    final progress = data.progressBps.clamp(0, 10000) / 10000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LevelBadge(level: data.level),
            const Spacer(),
            Text(
              '${data.totalXp} XP',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: WorkerColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: WorkerColors.row,
            color: WorkerColors.primary,
            semanticsLabel: 'Progress to next contribution level',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          data.isTopLevel || data.remainingCentiXp == null
              ? 'Highest contribution level'
              : '${formatCentiXp(data.remainingCentiXp!)} XP to ${_levelName(data.nextLevel!)}',
          style: const TextStyle(color: WorkerColors.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 20,
          runSpacing: 6,
          children: [
            _Fact(label: 'Verified tasks', value: '${data.verifiedTaskCount}'),
            if (data.acceptedProcessingMs != null)
              _Fact(label: 'Accepted processing', value: formatProcessingDuration(data.acceptedProcessingMs!)),
          ],
        ),
        const Divider(height: 28, color: WorkerColors.outlineVariant),
        _BoostRow(
          data: data,
          activating: activating,
          onActivate: () => _confirmAndActivate(context, data.boostPurchase, data.boost.bonusBps),
        ),
      ],
    );
  }

  Future<void> _confirmAndActivate(
    BuildContext context,
    ContributionBoostPurchase purchase,
    int bonusBps,
  ) async {
    final price = purchase.priceTokenMinorUnits;
    if (!purchase.enabled || price == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Activate Boost?'),
        content: Text(
          'This spends $price tokens from your balance. Boost adds ${formatBps(bonusBps)} XP to verified tasks '
          'for ${purchase.durationHours} hours or ${purchase.taskQuota} tasks, whichever ends first. '
          'It does not change task rewards.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Spend tokens')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final problem = await onActivateBoost();
    if (problem != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(boostProblemMessage(problem))),
      );
    }
  }
}

class _BoostRow extends StatelessWidget {
  const _BoostRow({required this.data, required this.activating, required this.onActivate});

  final WorkerContributionSummary data;
  final bool activating;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final boost = data.boost;
    final purchase = data.boostPurchase;
    if (boost.active) {
      return Row(
        children: [
          const Icon(Icons.bolt_rounded, color: WorkerColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Boost active · ${boost.remainingTasks ?? 0} tasks left'
              '${boost.expiresAt == null ? '' : ' · ends ${formatBoostEnd(boost.expiresAt!)}'}',
              style: const TextStyle(color: WorkerColors.onSurface, fontSize: 13),
            ),
          ),
        ],
      );
    }
    final price = purchase.priceTokenMinorUnits;
    final canBuy = purchase.enabled && price != null && !activating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt_outlined, color: WorkerColors.dim, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Boost: +${formatBps(boost.bonusBps)} XP',
                style: const TextStyle(color: WorkerColors.onSurface, fontSize: 13),
              ),
            ),
            FilledButton(
              onPressed: canBuy ? onActivate : null,
              child: Text(price == null ? 'Activate' : 'Activate · $price tokens'),
            ),
          ],
        ),
        if (!purchase.enabled) ...[
          const SizedBox(height: 6),
          Text(
            boostBlockedMessage(purchase.blockedReason),
            style: const TextStyle(color: WorkerColors.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final String level;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      'bronze' => WorkerColors.goldDeep,
      'silver' => WorkerColors.onSurfaceVariant,
      'gold' => WorkerColors.primary,
      'platinum' => WorkerColors.goldSoft,
      _ => WorkerColors.dim,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded, size: 16, color: color),
          const SizedBox(width: 6),
          Text(_levelName(level), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label  ', style: const TextStyle(color: WorkerColors.onSurfaceVariant)),
          TextSpan(text: value, style: const TextStyle(color: WorkerColors.onSurface, fontWeight: FontWeight.w600)),
        ],
      ),
      style: const TextStyle(fontSize: 13),
    );
  }
}

String _levelName(String level) =>
    level.isEmpty ? level : '${level[0].toUpperCase()}${level.substring(1)}';

String formatBps(int bps) {
  final whole = bps ~/ 100;
  final rest = bps % 100;
  return rest == 0 ? '$whole%' : '$whole.${rest.toString().padLeft(2, '0')}%';
}

String formatProcessingDuration(int ms) {
  final totalMinutes = ms ~/ 60000;
  if (totalMinutes < 1) {
    return '${ms ~/ 1000}s';
  }
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return hours == 0 ? '${minutes}m' : '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

String formatBoostEnd(DateTime utc) {
  final local = utc.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String boostBlockedMessage(String? reason) => switch (reason) {
      'BOOST_PRICE_NOT_CONFIGURED' => 'Boost is not available yet: no token price has been set.',
      'TOKEN_WALLET_UNAVAILABLE' => 'Boost is not available yet: contributor tokens are not connected.',
      'BOOST_ALREADY_ACTIVE' => 'A Boost is already active.',
      _ => 'Boost is not available right now.',
    };

String contributionLoadErrorMessage(String? code) => switch (code) {
      'HTTP_404' =>
        'Contribution sync is not on the worker backend yet. Restart worker-registry, then tap Retry.',
      'HTTP_500' || 'HTTP_503' =>
        'Contribution sync failed on the server. Apply database migrations, then tap Retry.',
      null => 'Contribution level could not be loaded.',
      _ => 'Contribution level could not be loaded ($code). Tap Retry.',
    };

String boostProblemMessage(String code) => switch (code) {
      'TOKEN_DEBIT_FAILED' => 'Not enough tokens. Boost was not activated.',
      'BOOST_ALREADY_ACTIVE' => 'A Boost is already active.',
      'BOOST_PRICE_NOT_CONFIGURED' || 'TOKEN_WALLET_UNAVAILABLE' => boostBlockedMessage(code),
      _ => 'Boost could not be activated. No tokens were spent.',
    };
