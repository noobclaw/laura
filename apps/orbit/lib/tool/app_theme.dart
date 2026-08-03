import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/branding.dart';

/// Orbit's art direction: a night sky you are looking *up* into.
///
/// Three fixed brand accents carry the meaning — a luminous cyan for the orbital
/// track, a warm amber for the moment of culmination, and a deep navy for space
/// itself — while surfaces and text come from the seeded scheme so both
/// brightnesses stay coherent. Dark mode is the app's home; light mode is a
/// clear pre-dawn sky rather than a washed-out inversion.
const Color kOrbitCyan = Color(0xFF3FE0C8); // the satellite's track
const Color kSignalAmber = Color(0xFFFFC24D); // culmination, "visible now"
const Color kDeepSpace = Color(0xFF070B18); // the sky between the stars
const Color kEclipseViolet = Color(0xFF7C6BFF); // in shadow / not visible

ThemeData buildOrbitTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: Branding.seedColor,
    brightness: brightness,
  );

  final scheme = base.copyWith(
    secondary: kOrbitCyan,
    onSecondary: const Color(0xFF00312B),
    tertiary: kSignalAmber,
    onTertiary: const Color(0xFF3A2600),
    surface: isDark ? kDeepSpace : const Color(0xFFF7F9FF),
    surfaceContainerLowest:
        isDark ? const Color(0xFF04070F) : const Color(0xFFFFFFFF),
    surfaceContainerLow:
        isDark ? const Color(0xFF0C1121) : const Color(0xFFF1F5FE),
    surfaceContainer:
        isDark ? const Color(0xFF111830) : const Color(0xFFEAF0FC),
    surfaceContainerHigh:
        isDark ? const Color(0xFF17203D) : const Color(0xFFE3EAF9),
    surfaceContainerHighest:
        isDark ? const Color(0xFF1E294C) : const Color(0xFFDCE4F5),
  );

  final theme = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    useMaterial3: true,
  );

  const tab = <FontFeature>[FontFeature.tabularFigures()];
  return theme.copyWith(
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? const Color(0xFF0C1121) : scheme.surface,
      indicatorColor: kOrbitCyan.withValues(alpha: isDark ? 0.22 : 0.30),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
      thickness: 1,
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    textTheme: theme.textTheme.copyWith(
      displayLarge: theme.textTheme.displayLarge?.copyWith(
          fontFeatures: tab, fontWeight: FontWeight.w700, letterSpacing: -1.5),
      displayMedium: theme.textTheme.displayMedium?.copyWith(
          fontFeatures: tab, fontWeight: FontWeight.w700, letterSpacing: -1.0),
      displaySmall: theme.textTheme.displaySmall
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      headlineMedium: theme.textTheme.headlineMedium
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      headlineSmall: theme.textTheme.headlineSmall
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      titleLarge: theme.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      labelLarge: theme.textTheme.labelLarge?.copyWith(letterSpacing: 0.1),
    ),
  );
}

/// The gradient behind every hero surface: deep space fading toward the horizon
/// glow. Tuned separately per brightness so the light theme reads as pre-dawn
/// rather than as a grey box.
LinearGradient skyGradient(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: isDark
        ? const [Color(0xFF0A1330), Color(0xFF12244F), Color(0xFF1B3A63)]
        : const [Color(0xFF1B2B57), Color(0xFF294A82), Color(0xFF3E6FA5)],
    stops: const [0.0, 0.55, 1.0],
  );
}

/// A deterministic scatter of stars for hero backgrounds. Deterministic matters:
/// the field must not reshuffle on every rebuild, or the hero shimmers whenever
/// the countdown ticks.
class StarFieldPainter extends CustomPainter {
  const StarFieldPainter({this.seed = 7, this.count = 70, this.opacity = 1.0});

  final int seed;
  final int count;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < count; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      final r = 0.4 + rng.nextDouble() * 1.3;
      // Brighter stars cluster toward the top, like a sky above a lit horizon.
      final fade = (1.0 - dy / size.height).clamp(0.15, 1.0);
      paint.color = Colors.white
          .withValues(alpha: (0.15 + rng.nextDouble() * 0.55) * fade * opacity);
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(StarFieldPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.count != count ||
      oldDelegate.opacity != opacity;
}
