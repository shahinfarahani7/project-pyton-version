import 'package:flutter/material.dart';

import '../worker_theme.dart';

/// Display DTO from authenticated server uptime summary (not client-side scoring).
class WorkerUptimeProgress {
  const WorkerUptimeProgress({
    required this.level,
    required this.nextLevel,
    required this.actualUptimeMs,
    required this.boosterBonusMs,
    required this.creditedLevelTimeMs,
    required this.remainingLevelTimeMs,
    required this.progressBps,
    required this.boosterActive,
    required this.boosterMultiplierBps,
    required this.boosterExpiresAt,
    required this.boosterUnavailableReason,
  });

  final String level;
  final String? nextLevel;
  final int actualUptimeMs;
  final int boosterBonusMs;
  final int creditedLevelTimeMs;
  final int? remainingLevelTimeMs;
  final int progressBps;
  final bool boosterActive;
  final int boosterMultiplierBps;
  final DateTime? boosterExpiresAt;
  final String? boosterUnavailableReason;

  bool get isTopLevel => nextLevel == null;
}

/// Compact participation level + uptime progress on the home dashboard.
class WorkerUptimeDashboardSection extends StatelessWidget {
  const WorkerUptimeDashboardSection({
    super.key,
    required this.uptime,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  final WorkerUptimeProgress? uptime;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final data = uptime;
    if (data == null) {
      return _UnavailableCard(loading: loading, error: error, onRetry: onRetry);
    }
    return _LoadedCard(
      data: data,
      loading: loading,
      error: error,
      onRetry: onRetry,
    );
  }
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({required this.loading, this.error, this.onRetry});

  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('dashboard-uptime-unavailable'),
      padding: const EdgeInsets.all(22),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading) ...[
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            loading
                ? 'Loading verified uptime…'
                : error != null
                ? 'Uptime progress could not be loaded.'
                : 'Uptime progress is not connected yet.',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your level will appear when verified uptime is available.',
            style: TextStyle(
              color: WorkerColors.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          if (!loading && onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}

class _LoadedCard extends StatelessWidget {
  const _LoadedCard({
    required this.data,
    required this.loading,
    this.error,
    this.onRetry,
  });

  final WorkerUptimeProgress data;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _levelColor(data.level);
    final progress = data.progressBps.clamp(0, 10000) / 10000;
    return Container(
      key: const ValueKey('dashboard-uptime-loaded'),
      padding: const EdgeInsets.all(22),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading || error != null) ...[
            Text(
              loading
                  ? 'Updating uptime…'
                  : 'Update unavailable. Showing last received values.',
              style: const TextStyle(color: WorkerColors.warning, fontSize: 12),
            ),
            if (!loading && onRetry != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              _LevelBadge(level: data.level, color: color),
              const Spacer(),
              Text(
                formatMissionTime(data.creditedLevelTimeMs),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: WorkerColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Total level time (verified uptime + Booster bonus)',
            style: TextStyle(
              color: WorkerColors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: WorkerColors.row,
              color: WorkerColors.primary,
              semanticsLabel: data.isTopLevel
                  ? 'Highest contribution level'
                  : 'Progress within current level',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.isTopLevel
                ? 'Highest contribution level'
                : data.remainingLevelTimeMs == null
                ? 'Time to the next level is unavailable.'
                : '${formatMissionTime(data.remainingLevelTimeMs!)} level time to ${_levelName(data.nextLevel!)}',
            style: const TextStyle(
              color: WorkerColors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 20,
            runSpacing: 6,
            children: [
              _Fact(
                label: 'Verified uptime',
                value: formatMissionTime(data.actualUptimeMs),
              ),
              _Fact(
                label: 'Booster bonus',
                value: '+${formatMissionTime(data.boosterBonusMs)}',
              ),
            ],
          ),
          const Divider(height: 28, color: WorkerColors.outlineVariant),
          _BoosterRow(data: data),
        ],
      ),
    );
  }
}

class _BoosterRow extends StatelessWidget {
  const _BoosterRow({required this.data});

  final WorkerUptimeProgress data;

  @override
  Widget build(BuildContext context) {
    if (data.boosterActive) {
      return Row(
        children: [
          const Icon(Icons.bolt_rounded, color: WorkerColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Uptime Booster active · ${formatMissionMultiplier(data.boosterMultiplierBps)} level progress'
              '${data.boosterExpiresAt == null ? '' : ' · ends ${data.boosterExpiresAt!.toUtc().toIso8601String()}'}',
              style: const TextStyle(
                color: WorkerColors.onSurface,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt_outlined, color: WorkerColors.dim, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Uptime Booster',
                style: TextStyle(color: WorkerColors.onSurface, fontSize: 13),
              ),
            ),
            const FilledButton(
              onPressed: null,
              child: Text('Activate Booster'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          data.boosterUnavailableReason ??
              'Booster purchase is not connected yet.',
          style: const TextStyle(
            color: WorkerColors.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, required this.color});

  final String level;
  final Color color;

  @override
  Widget build(BuildContext context) {
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
          Text(
            _levelName(level),
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
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
          TextSpan(
            text: '$label  ',
            style: const TextStyle(color: WorkerColors.onSurfaceVariant),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: WorkerColors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 13),
    );
  }
}

Color _levelColor(String level) => switch (level) {
  'bronze' => WorkerColors.goldDeep,
  'silver' => WorkerColors.onSurfaceVariant,
  'gold' => WorkerColors.primary,
  'platinum' => WorkerColors.goldSoft,
  _ => WorkerColors.dim,
};

String _levelName(String level) =>
    level.isEmpty ? level : '${level[0].toUpperCase()}${level.substring(1)}';

String formatMissionTime(int ms) {
  final minutes = ms ~/ 60000;
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

String formatMissionMultiplier(int bps) {
  final whole = bps ~/ 10000;
  final fraction = (bps % 10000)
      .toString()
      .padLeft(4, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole×' : '$whole.$fraction×';
}
