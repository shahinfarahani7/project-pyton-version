import 'package:flutter/material.dart';

/// FibonAI palette (DESIGN.txt / fibonai-palette.svg), dark theme.
abstract final class WorkerColors {
  static const primary = Color(0xFFCDAE6F);
  static const primaryContainer = Color(0xFF262F38);
  static const secondary = Color(0xFFCDAE6F);
  static const goldDeep = Color(0xFFC0A064);
  static const goldSoft = Color(0xFFF1E6CF);
  static const brandLine = Color(0xFFECE8DF);
  static const canvas = Color(0xFF0B0C0F);
  static const surface = Color(0xFF0B0C0F);
  static const surfaceDim = Color(0xFF101216);
  static const surfaceContainer = Color(0xFF101216);
  static const surfaceContainerHigh = Color(0xFF15171B);
  static const row = Color(0xFF1A1C20);
  static const onSurface = Color(0xFFFFFFFF);
  static const onSurfaceVariant = Color(0xFFB3B5BD);
  static const dim = Color(0xFF7A7C86);
  static const outlineVariant = Color(0x17FFFFFF);
  static const outlineHover = Color(0x33FFFFFF);
  static const success = Color(0xFF19C7B4);
  static const warning = Color(0xFFCDAE6F);
  static const error = Color(0xFFE2456B);
  static const info = Color(0xFF2C84FF);
  static const accentOrange = Color(0xFFA6C0CB);
}

ThemeData buildWorkerTheme() {
  const scheme = ColorScheme.dark(
    primary: WorkerColors.primary,
    onPrimary: WorkerColors.canvas,
    primaryContainer: WorkerColors.primaryContainer,
    onPrimaryContainer: WorkerColors.goldSoft,
    secondary: WorkerColors.secondary,
    onSecondary: WorkerColors.canvas,
    surface: WorkerColors.surface,
    onSurface: WorkerColors.onSurface,
    onSurfaceVariant: WorkerColors.onSurfaceVariant,
    outline: WorkerColors.dim,
    outlineVariant: WorkerColors.outlineVariant,
    error: WorkerColors.error,
    onError: WorkerColors.canvas,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: WorkerColors.surface,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: WorkerColors.primary,
      linearTrackColor: WorkerColors.row,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WorkerColors.brandLine,
        side: const BorderSide(color: WorkerColors.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WorkerColors.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: WorkerColors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: WorkerColors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: WorkerColors.primary),
      ),
    ),
    cardTheme: CardThemeData(
      color: WorkerColors.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: WorkerColors.outlineVariant),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: WorkerColors.surfaceDim,
      foregroundColor: WorkerColors.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: WorkerColors.surfaceDim,
      indicatorColor: WorkerColors.primary.withValues(alpha: 0.09),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? WorkerColors.primary : WorkerColors.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? WorkerColors.primary : WorkerColors.onSurfaceVariant,
          size: 22,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WorkerColors.primary,
        foregroundColor: WorkerColors.canvas,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: WorkerColors.secondary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return WorkerColors.primary;
        return WorkerColors.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return WorkerColors.primary.withValues(alpha: 0.35);
        }
        return WorkerColors.row;
      }),
    ),
    dividerTheme: const DividerThemeData(color: WorkerColors.outlineVariant),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: WorkerColors.surfaceContainerHigh,
      contentTextStyle: const TextStyle(color: WorkerColors.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: WorkerColors.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

BoxDecoration workerPanelDecoration({Color? borderColor}) {
  return BoxDecoration(
    color: WorkerColors.surfaceContainer,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: borderColor ?? WorkerColors.outlineVariant),
  );
}

LinearGradient workerHeroGradient() {
  return const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF15171B), Color(0xFF262F38)],
  );
}

/// FibonAI mark: line-colour frames with gold fills, per DESIGN.txt section 2.
class FibonaiMark extends StatelessWidget {
  const FibonaiMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _FibonaiMarkPainter()),
    );
  }
}

class _FibonaiMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = WorkerColors.brandLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.085;
    final gold = Paint()..color = WorkerColors.goldDeep;

    canvas.drawRect(Rect.fromLTRB(s * 0.06, s * 0.06, s * 0.66, s * 0.94), stroke);
    canvas.drawRect(Rect.fromLTRB(s * 0.20, s * 0.06, s * 0.94, s * 0.62), stroke);

    final arc = Path()
      ..moveTo(s * 0.30, s * 0.50)
      ..lineTo(s * 0.30, s * 0.34)
      ..arcToPoint(Offset(s * 0.48, s * 0.16), radius: Radius.circular(s * 0.18))
      ..lineTo(s * 0.56, s * 0.16)
      ..lineTo(s * 0.56, s * 0.50)
      ..close();
    canvas.drawPath(arc, gold);
    canvas.drawRect(Rect.fromLTRB(s * 0.66, s * 0.16, s * 0.82, s * 0.50), gold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
