import 'package:flutter/material.dart';

import 'worker_theme.dart';

/// Draws the FibonAI mark outline, then fills it.
class FibonaiSplashScreen extends StatefulWidget {
  const FibonaiSplashScreen({super.key, this.onFinished});

  final VoidCallback? onFinished;

  @override
  State<FibonaiSplashScreen> createState() => _FibonaiSplashScreenState();
}

class _FibonaiSplashScreenState extends State<FibonaiSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward().whenComplete(() {
        widget.onFinished?.call();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WorkerColors.canvas,
      body: Center(
        child: Semantics(
          label: 'FibonAI logo',
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                size: const Size.square(220),
                painter: FibonaiMarkPainter(progress: _controller.value),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Stroke-then-fill of the mark measured from the brand asset.
class FibonaiMarkPainter extends CustomPainter {
  FibonaiMarkPainter({required this.progress});

  final double progress;

  static const _gold = Color(0xFFCDAE6F);

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = _fit(size);
    canvas.save();
    canvas.translate(fitted.left, fitted.top);
    canvas.scale(fitted.width / FibonaiMarkPaths.viewWidth);

    final left = FibonaiMarkPaths.leftShape();
    final bar = FibonaiMarkPaths.bar();
    final leftLength = left.computeMetrics().first.length;
    final barLength = bar.computeMetrics().first.length;
    final drawn = progress.clamp(0.0, 1.0) * (leftLength + barLength);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _gold;
    _paintTrim(canvas, left, stroke, drawn);
    _paintTrim(canvas, bar, stroke, drawn - leftLength);

    final fillT = ((progress - 0.72) / 0.28).clamp(0.0, 1.0);
    if (fillT > 0) {
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = _gold.withValues(alpha: fillT);
      canvas.drawPath(left, fill);
      canvas.drawPath(bar, fill);
    }
    canvas.restore();
  }

  Rect _fit(Size size) {
    final scale = size.width / FibonaiMarkPaths.viewWidth;
    final height = FibonaiMarkPaths.viewHeight * scale;
    final fitted = Size(size.width, height);
    return Alignment.center.inscribe(fitted, Offset.zero & size);
  }

  void _paintTrim(Canvas canvas, Path source, Paint paint, double length) {
    if (length <= 0) {
      return;
    }
    for (final metric in source.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, length), paint);
    }
  }

  @override
  bool shouldRepaint(FibonaiMarkPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Paths in the brand PNG's mark box: x 80–237, y 44–141.
abstract final class FibonaiMarkPaths {
  static const viewWidth = 157.0;
  static const viewHeight = 97.0;

  static double _x(double px) => px - 80;
  static double _y(double py) => py - 44;

  static Path leftShape() {
    return Path()
      ..moveTo(_x(151), _y(44))
      ..cubicTo(_x(124), _y(50), _x(100), _y(66), _x(86), _y(85))
      ..cubicTo(_x(81), _y(94), _x(80), _y(101), _x(80), _y(107))
      ..lineTo(_x(80), _y(141))
      ..lineTo(_x(151), _y(141))
      ..close();
  }

  static Path bar() {
    return Path()..addRect(Rect.fromLTRB(_x(202), _y(45), _x(237), _y(141)));
  }
}
