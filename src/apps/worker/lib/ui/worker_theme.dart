import 'package:flutter/material.dart';

/// EdgeMint worker portal palette — aligned with customer portal dark theme.
abstract final class WorkerColors {
  static const primary = Color(0xFF7C4DFF);
  static const primaryContainer = Color(0xFF5B21B6);
  static const secondary = Color(0xFFA78BFA);
  static const surface = Color(0xFF0F172A);
  static const surfaceDim = Color(0xFF0B1220);
  static const surfaceContainer = Color(0xFF1E293B);
  static const surfaceContainerHigh = Color(0xFF243044);
  static const onSurface = Color(0xFFF1F5F9);
  static const onSurfaceVariant = Color(0xFF94A3B8);
  static const outlineVariant = Color(0xFF334155);
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFBBF24);
  static const error = Color(0xFFF87171);
  static const info = Color(0xFF3B82F6);
  static const accentOrange = Color(0xFFF97316);
}

ThemeData buildWorkerTheme() {
  const scheme = ColorScheme.dark(
    primary: WorkerColors.primary,
    onPrimary: Colors.white,
    primaryContainer: WorkerColors.primaryContainer,
    onPrimaryContainer: Color(0xFFEDE9FE),
    secondary: WorkerColors.secondary,
    onSecondary: Color(0xFF1E1B4B),
    surface: WorkerColors.surface,
    onSurface: WorkerColors.onSurface,
    onSurfaceVariant: WorkerColors.onSurfaceVariant,
    outlineVariant: WorkerColors.outlineVariant,
    error: WorkerColors.error,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: WorkerColors.surface,
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
      indicatorColor: WorkerColors.primary.withValues(alpha: 0.22),
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
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        return WorkerColors.outlineVariant;
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
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.25),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

LinearGradient workerHeroGradient() {
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      WorkerColors.primaryContainer.withValues(alpha: 0.45),
      WorkerColors.surface,
    ],
  );
}
