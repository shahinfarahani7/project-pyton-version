import 'dart:math' as math;
import 'dart:ui' show ClipOp;

import 'package:flutter/material.dart';

import 'worker_theme.dart';

/// Strokes the FibonAI mark frames, traces the gold shapes, then fills them.
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
                size: const Size.square(200),
                painter: FibonaiMarkPainter(progress: _controller.value),
              );
            },
          ),
        ),
      ),
    );
  }
}

class FibonaiMarkPainter extends CustomPainter {
  FibonaiMarkPainter({required this.progress});

  final double progress;

  static const _frameEnd = 0.68;
  static const _goldTraceStart = 0.38;
  static const _goldTraceEnd = 0.8;
  static const _goldFillStart = 0.72;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.clamp(0.0, 1.0);
    final scale = math.min(
      size.width / FibonaiMarkPaths.viewWidth,
      size.height / FibonaiMarkPaths.viewHeight,
    );
    canvas.save();
    canvas.translate(
      (size.width - FibonaiMarkPaths.viewWidth * scale) / 2,
      (size.height - FibonaiMarkPaths.viewHeight * scale) / 2,
    );
    canvas.scale(scale);

    final frameT = Curves.easeInOutCubic.transform(
      (t / _frameEnd).clamp(0.0, 1.0),
    );
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = FibonaiMarkPaths.frameWidth
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter
      ..color = WorkerColors.brandLine;
    _trace(canvas, FibonaiMarkPaths.lowerFrame(), frame, frameT);
    canvas.save();
    canvas.clipRect(FibonaiMarkPaths.innerArcTopCut, clipOp: ClipOp.difference);
    _trace(canvas, FibonaiMarkPaths.upperFrame(), frame, frameT);
    canvas.restore();

    final gold = [FibonaiMarkPaths.goldQuarter(), FibonaiMarkPaths.goldBar()];
    final traceT = Curves.easeInOut.transform(
      ((t - _goldTraceStart) / (_goldTraceEnd - _goldTraceStart))
          .clamp(0.0, 1.0),
    );
    final fillT = ((t - _goldFillStart) / (1 - _goldFillStart)).clamp(0.0, 1.0);
    if (traceT > 0 && fillT < 1) {
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.miter
        ..color = WorkerColors.primary.withValues(alpha: 1 - fillT);
      for (final shape in gold) {
        _trace(canvas, shape, outline, traceT);
      }
    }
    if (fillT > 0) {
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = WorkerColors.primary.withValues(alpha: fillT);
      for (final shape in gold) {
        canvas.drawPath(shape, fill);
      }
    }
    canvas.restore();
  }

  /// Draws the first [fraction] of [path]'s length.
  void _trace(Canvas canvas, Path path, Paint paint, double fraction) {
    if (fraction <= 0) {
      return;
    }
    final metrics = path.computeMetrics().toList();
    var remaining =
        fraction * metrics.fold<double>(0, (sum, metric) => sum + metric.length);
    for (final metric in metrics) {
      if (remaining <= 0) break;
      final length = math.min(remaining, metric.length);
      canvas.drawPath(metric.extractPath(0, length), paint);
      remaining -= length;
    }
  }

  @override
  bool shouldRepaint(FibonaiMarkPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Centerlines measured from tool/brand/fibonai-mark-light.png (332×314).
/// The mark's ink box starts at (33, 33) and is 266×247 px.
abstract final class FibonaiMarkPaths {
  static const viewWidth = 266.0;
  static const viewHeight = 247.0;
  static const frameWidth = 23.0;

  static const _origin = 33.0;
  static const _arcCenter = Offset(177 - _origin, 141 - _origin);
  static const _arcRadius = 96.0;
  static const _goldRadius = 72.0;

  static Offset _p(double x, double y) => Offset(x - _origin, y - _origin);

  /// Clipped away so the inner arc ends flat, level with the gold tops.
  /// No other upper-frame ink lies in this box.
  static final Rect innerArcTopCut =
      Rect.fromLTRB(60 - _origin, -_origin, 150 - _origin, 69 - _origin);

  /// Open frame: top bar, left side, bottom, short right side.
  static Path lowerFrame() {
    final start = _p(177, 44.5);
    final topLeft = _p(44.5, 44.5);
    final bottomLeft = _p(44.5, 268.5);
    final bottomRight = _p(201.5, 268.5);
    final end = _p(201.5, 215);
    return Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(topLeft.dx, topLeft.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(end.dx, end.dy);
  }

  /// One stroke: inner arc, down, across the bottom, up the right side,
  /// back along the top and down the short left side.
  static Path upperFrame() {
    final startAngle = math.pi + math.asin((141 - 60) / _arcRadius);
    final path = Path()
      ..addArc(
        Rect.fromCircle(center: _arcCenter, radius: _arcRadius),
        startAngle,
        math.pi - startAngle,
      );
    for (final point in [
      _p(81, 190.5),
      _p(287.5, 190.5),
      _p(287.5, 44.5),
      _p(201.5, 44.5),
      _p(201.5, 166),
    ]) {
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }

  /// Quarter-round block: 72 px radius on the top-left corner.
  static Path goldQuarter() {
    final bottomLeft = _p(105, 166);
    final arcStart = _p(105, 141);
    final bottomRight = _p(177, 166);
    return Path()
      ..moveTo(bottomLeft.dx, bottomLeft.dy)
      ..lineTo(arcStart.dx, arcStart.dy)
      ..arcTo(
        Rect.fromCircle(center: _arcCenter, radius: _goldRadius),
        math.pi,
        math.pi / 2,
        false,
      )
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..close();
  }

  static Path goldBar() {
    final topLeft = _p(226, 69);
    final bottomRight = _p(263, 166);
    return Path()..addRect(Rect.fromPoints(topLeft, bottomRight));
  }
}
