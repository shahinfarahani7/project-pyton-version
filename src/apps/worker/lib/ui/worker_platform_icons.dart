import 'package:flutter/material.dart';

import 'tabs/worker_mission_catalog.dart';
import 'worker_theme.dart';

/// Brand-colored marks for social mission rows (Material has no official logos).
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
    final (Color bg, Widget mark) = switch (kind) {
      WorkerMissionKind.socialTelegram => (
          const Color(0xFF229ED9),
          Icon(Icons.send_rounded, color: Colors.white, size: size * 0.52),
        ),
      WorkerMissionKind.socialDiscord => (
          const Color(0xFF5865F2),
          _DiscordMark(size: size * 0.55),
        ),
      WorkerMissionKind.socialTwitter => (
          const Color(0xFF0F1419),
          Text(
            '𝕏',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.46,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
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
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: mark,
    );
  }
}

class _DiscordMark extends StatelessWidget {
  const _DiscordMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DiscordMarkPainter(),
    );
  }
}

class _DiscordMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final w = size.width;
    final h = size.height;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.08, h * 0.22, w * 0.84, h * 0.56),
        Radius.circular(h * 0.28),
      ),
      paint,
    );
    canvas.drawCircle(Offset(w * 0.34, h * 0.48), w * 0.07, paint);
    canvas.drawCircle(Offset(w * 0.66, h * 0.48), w * 0.07, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
