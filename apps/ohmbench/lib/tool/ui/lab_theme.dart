import 'package:flutter/material.dart';

import '../../bench/base_theme.dart';

/// The bench: OhmBench's canvas is always a dark instrument surface — a
/// scope screen, not a sheet of paper — whatever the phone's theme. The app
/// chrome around it (library, sheets, settings) follows the system theme.
abstract final class Bench {
  static const Color background = Color(0xFF0A1016);
  static const Color backgroundTop = Color(0xFF0E1A23);
  static const Color gridDot = Color(0xFF1E2E3A);
  static const Color gridMajor = Color(0xFF16232D);
  static const Color ink = Color(0xFFE4EDF2);
  static const Color inkDim = Color(0xFF8FA3B0);
  static const Color wireIdle = Color(0xFF9DB2C0);
  static const Color neutral = Color(0xFF5E707C);

  /// Positive voltage, the scope-trace cyan of the brand (hue 198).
  static const Color positive = Color(0xFF3FD4F7);

  /// Negative voltage.
  static const Color negative = Color(0xFFFF5C93);

  /// Moving charge. Warm, so it reads against both voltage colours.
  static const Color charge = Color(0xFFFFD66B);

  static const Color selection = Color(0xFF3FD4F7);
  static const Color warning = Color(0xFFFFB454);
  static const Color error = Color(0xFFFF6B6B);

  static const Color panel = Color(0xFF111C25);
  static const Color panelBorder = Color(0xFF223340);

  /// A voltage as a colour: grey at 0 V, cyan towards the run's highest
  /// voltage, magenta towards its most negative.
  static Color forVoltage(double volts, double peak) {
    if (peak <= 0 || !volts.isFinite) return neutral;
    final t = (volts / peak).clamp(-1.0, 1.0);
    // A gentle curve so a 1 V node in a 12 V circuit is visibly tinted.
    final k = Curves.easeOutCubic.transform(t.abs());
    return Color.lerp(neutral, t >= 0 ? positive : negative, k)!;
  }
}

/// The one theme OhmBench ships: the whole app is the bench.
///
/// Every other app from this project follows the phone's light/dark setting
/// on a tonal Material surface. OhmBench deliberately does not — library,
/// sheets, dialogs and settings all sit on the same dark instrument surface
/// as the canvas, with charge yellow as the action colour and scope cyan as
/// the data colour. One look, end to end, that is recognisably this app
/// (and not the shared template; see the 2026-09-22 4.3(a) rejection of a
/// sibling app).
ThemeData buildOhmTheme([Brightness _ = Brightness.dark]) {
  final base = buildBaseTheme(Brightness.dark);
  final scheme = base.colorScheme.copyWith(
    primary: Bench.charge,
    onPrimary: const Color(0xFF2B2100),
    primaryContainer: const Color(0xFF3A3108),
    onPrimaryContainer: const Color(0xFFFFE9A8),
    secondary: Bench.positive,
    onSecondary: const Color(0xFF00202B),
    secondaryContainer: const Color(0xFF0E3444),
    onSecondaryContainer: const Color(0xFFBDEFFF),
    tertiary: Bench.negative,
    surface: Bench.background,
    onSurface: Bench.ink,
    onSurfaceVariant: Bench.inkDim,
    surfaceContainerLowest: const Color(0xFF070C11),
    surfaceContainerLow: const Color(0xFF0D161D),
    surfaceContainer: Bench.panel,
    surfaceContainerHigh: const Color(0xFF142430),
    surfaceContainerHighest: const Color(0xFF1B2E3B),
    outline: const Color(0xFF2E4452),
    outlineVariant: Bench.panelBorder,
    error: Bench.error,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: Bench.background,
    canvasColor: Bench.background,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Bench.background,
      foregroundColor: Bench.ink,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: Bench.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Bench.panelBorder),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF0D161D),
      modalBackgroundColor: Color(0xFF0D161D),
      surfaceTintColor: Colors.transparent,
      dragHandleColor: Color(0xFF3A5363),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: Bench.panelBorder),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFF0F1B24),
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xFF1B2E3B),
      contentTextStyle: TextStyle(color: Bench.ink),
      actionTextColor: Bench.charge,
    ),
    dividerTheme: const DividerThemeData(color: Bench.panelBorder),
  );
}
