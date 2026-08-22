import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'worker_theme.dart';

class WorkerKpiCard extends StatelessWidget {
  const WorkerKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.trend,
    required this.icon,
    required this.accent,
    this.sparkline,
    this.trailing,
  });

  final String label;
  final String value;
  final String trend;
  final IconData icon;
  final Color accent;
  final List<double>? sparkline;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          Text(label, style: _muted(context)),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: WorkerColors.onSurface,
                ),
          ),
          const SizedBox(height: 4),
          Text(trend, style: TextStyle(fontSize: 12, color: accent)),
          if (sparkline != null && sparkline!.length >= 2) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: CustomPaint(
                painter: _SparklinePainter(values: sparkline!, color: accent),
                size: const Size(double.infinity, 36),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class WorkerSectionHeader extends StatelessWidget {
  const WorkerSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: WorkerColors.onSurface,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: _muted(context)),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class WorkerStatusChip extends StatelessWidget {
  const WorkerStatusChip({
    super.key,
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? WorkerColors.success : WorkerColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class WorkerQuickAction extends StatelessWidget {
  const WorkerQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WorkerColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: WorkerColors.secondary),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: WorkerColors.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkerReadinessRow extends StatelessWidget {
  const WorkerReadinessRow({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ok = switch (value) {
      'Offline' || 'Pending' || 'Critical' || 'Throttled' => false,
      _ when value.contains('(emulator AC)') => true,
      _ => true,
    };
    final color = ok ? WorkerColors.success : WorkerColors.warning;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: WorkerColors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(color: WorkerColors.onSurface)),
          ),
          Text(value, style: _muted(context)),
          const SizedBox(width: 8),
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            size: 18,
            color: color,
          ),
        ],
      ),
    );
  }
}

class WorkerLineChart extends StatelessWidget {
  const WorkerLineChart({
    super.key,
    required this.values,
    required this.color,
    this.height = 120,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _AreaLinePainter(values: values, color: color),
      ),
    );
  }
}

class WorkerDonutChart extends StatelessWidget {
  const WorkerDonutChart({
    super.key,
    required this.segments,
    required this.centerLabel,
    this.size = 160,
  });

  final List<WorkerDonutSegment> segments;
  final String centerLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DonutPainter(segments: segments),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text('tasks', style: _muted(context)),
            ],
          ),
        ],
      ),
    );
  }
}

class WorkerDonutSegment {
  const WorkerDonutSegment(this.label, this.value, this.color);

  final String label;
  final double value;
  final Color color;
}

class WorkerMascotHero extends StatelessWidget {
  const WorkerMascotHero({
    super.key,
    required this.listening,
    required this.subtitle,
  });

  final bool listening;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: workerHeroGradient(),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WorkerColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  WorkerColors.primary.withValues(alpha: 0.5),
                  WorkerColors.primaryContainer.withValues(alpha: 0.2),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: WorkerColors.primary.withValues(alpha: 0.45),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.smart_toy_rounded, size: 52, color: Colors.white),
          ),
          const SizedBox(height: 16),
          WorkerStatusChip(
            label: listening ? 'Listening for tasks' : 'Unavailable',
            active: listening,
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: _muted(context), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class WorkerSystemStatusBar extends StatelessWidget {
  const WorkerSystemStatusBar({
    super.key,
    required this.online,
    required this.lastSync,
  });

  final bool online;
  final String lastSync;

  @override
  Widget build(BuildContext context) {
    final color = online ? WorkerColors.success : WorkerColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(online ? Icons.verified_user : Icons.warning_amber_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              online
                  ? 'All systems operational — last sync $lastSync'
                  : 'Backend offline — check gateway connection',
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle _muted(BuildContext context) {
  return Theme.of(context).textTheme.bodySmall?.copyWith(
        color: WorkerColors.onSurfaceVariant,
      ) ??
      const TextStyle(color: WorkerColors.onSurfaceVariant, fontSize: 12);
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV).clamp(0.001, double.infinity);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - ((values[i] - minV) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _AreaLinePainter extends CustomPainter {
  _AreaLinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV).clamp(0.001, double.infinity);
    final line = Path();
    final fill = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - ((values[i] - minV) / range) * (size.height - 8) - 4;
      if (i == 0) {
        line.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        line.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _AreaLinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments});

  final List<WorkerDonutSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (sum, s) => sum + s.value);
    if (total <= 0) return;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    var start = -math.pi / 2;
    for (final segment in segments) {
      final sweep = (segment.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect.deflate(12), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => oldDelegate.segments != segments;
}
