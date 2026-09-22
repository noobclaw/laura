import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

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

/// App theme: the shell's premium defaults on the OhmBench seed, with a
/// deeper, bluer dark surface so the chrome sits comfortably next to the
/// bench.
ThemeData buildOhmTheme(Brightness brightness) {
  final base = buildAppTheme(brightness);
  if (brightness == Brightness.light) return base;
  final scheme = base.colorScheme.copyWith(
    surface: const Color(0xFF0C141B),
    surfaceContainerLowest: const Color(0xFF080E13),
    surfaceContainerLow: const Color(0xFF101A22),
    surfaceContainer: const Color(0xFF13202A),
    surfaceContainerHigh: const Color(0xFF172631),
    surfaceContainerHighest: const Color(0xFF1C2D39),
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: base.cardTheme.copyWith(color: scheme.surfaceContainerHigh),
  );
}
