import 'package:flutter/material.dart';

import 'tabs/worker_mission_catalog.dart';
import 'worker_theme.dart';

/// Brand marks for social missions (simplified official shapes, not trademark assets).
class WorkerPlatformIcon extends StatelessWidget {
  const WorkerPlatformIcon({super.key, required this.kind, this.size = 28});

  final WorkerMissionKind kind;
  final double size;

  static bool isSocialKind(WorkerMissionKind kind) => switch (kind) {
        WorkerMissionKind.socialTelegram ||
        WorkerMissionKind.socialDiscord ||
        WorkerMissionKind.socialTwitter =>
          true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final spec = switch (kind) {
      WorkerMissionKind.socialTelegram => (
          const Color(0xFF26A5E4),
          _TelegramLogo(size: size * 0.58),
        ),
      WorkerMissionKind.socialDiscord => (
          const Color(0xFF5865F2),
          _DiscordLogo(size: size * 0.58, brandColor: const Color(0xFF5865F2)),
        ),
      WorkerMissionKind.socialTwitter => (
          const Color(0xFF000000),
          _XLogo(size: size * 0.55),
        ),
      _ => (
          WorkerColors.primary,
          Icon(Icons.link, size: size * 0.5, color: Colors.white),
        ),
    };

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: spec.$1,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      clipBehavior: Clip.antiAlias,
      child: spec.$2,
    );
  }
}

class _TelegramLogo extends StatelessWidget {
  const _TelegramLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * 1.05, size),
      painter: _TelegramLogoPainter(),
    );
  }
}

class _TelegramLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final w = size.width;
    final h = size.height;
    // Paper-plane mark (Telegram send icon proportions).
    final path = Path()
      ..moveTo(w * 0.22, h * 0.48)
      ..lineTo(w * 0.88, h * 0.14)
      ..lineTo(w * 0.72, h * 0.86)
      ..lineTo(w * 0.48, h * 0.62)
      ..lineTo(w * 0.36, h * 0.74)
      ..lineTo(w * 0.30, h * 0.56)
      ..close();
    canvas.drawPath(path, paint);
    final tail = Path()
      ..moveTo(w * 0.36, h * 0.74)
      ..lineTo(w * 0.34, h * 0.92)
      ..lineTo(w * 0.44, h * 0.68)
      ..close();
    canvas.drawPath(tail, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DiscordLogo extends StatelessWidget {
  const _DiscordLogo({required this.size, required this.brandColor});

  final double size;
  final Color brandColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DiscordLogoPainter(brandColor: brandColor),
    );
  }
}

class _DiscordLogoPainter extends CustomPainter {
  _DiscordLogoPainter({required this.brandColor});

  final Color brandColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = Paint()..color = Colors.white;
    // Clyde-style head (Discord app icon silhouette).
    final path = Path()
      ..moveTo(w * 0.16, h * 0.34)
      ..cubicTo(w * 0.38, h * 0.18, w * 0.62, h * 0.18, w * 0.84, h * 0.34)
      ..lineTo(w * 0.94, h * 0.58)
      ..cubicTo(w * 0.82, h * 0.68, w * 0.70, h * 0.74, w * 0.50, h * 0.76)
      ..cubicTo(w * 0.30, h * 0.74, w * 0.18, h * 0.68, w * 0.06, h * 0.58)
      ..close();
    canvas.drawPath(path, body);

    final eyePaint = Paint()..color = brandColor;
    canvas.drawCircle(Offset(w * 0.36, h * 0.46), w * 0.07, eyePaint);
    canvas.drawCircle(Offset(w * 0.64, h * 0.46), w * 0.07, eyePaint);

    final smile = Paint()
      ..color = brandColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.54),
        width: w * 0.22,
        height: h * 0.14,
      ),
      0.2,
      3.6,
      false,
      smile,
    );
  }

  @override
  bool shouldRepaint(covariant _DiscordLogoPainter oldDelegate) =>
      oldDelegate.brandColor != brandColor;
}

class _XLogo extends StatelessWidget {
  const _XLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _XLogoPainter(),
    );
  }
}

class _XLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round;
    final pad = size.width * 0.24;
    canvas.drawLine(
      Offset(pad, pad),
      Offset(size.width - pad, size.height - pad),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - pad, pad),
      Offset(pad, size.height - pad),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
