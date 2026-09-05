import 'package:flutter/material.dart';

import '../core/branding.dart';

/// TuneBench's art direction: a dim rehearsal room with one bright meter.
///
/// Surfaces are a deep indigo-black in the dark theme (the app's home — most
/// practice happens on a music stand at night) and a cool paper white in
/// light. Three fixed accents carry meaning everywhere: green = in tune /
/// correct, amber = the beat / attention, coral = flat-or-sharp / wrong.
const Color kInTuneGreen = Color(0xFF3DDC97);
const Color kBeatAmber = Color(0xFFFFB454);
const Color kOffCoral = Color(0xFFFF6B7A);
const Color kInkDark = Color(0xFF0B0D1A);

ThemeData buildTuneTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: Branding.seedColor,
    brightness: brightness,
  );

  final scheme = base.copyWith(
    tertiary: kBeatAmber,
    onTertiary: const Color(0xFF3A2600),
    surface: isDark ? kInkDark : const Color(0xFFF6F7FC),
    surfaceContainerLowest: isDark ? const Color(0xFF07080F) : Colors.white,
    surfaceContainerLow: isDark ? const Color(0xFF11142A) : const Color(0xFFEFF1FA),
    surfaceContainer: isDark ? const Color(0xFF171B36) : const Color(0xFFE8EBF7),
    surfaceContainerHigh: isDark ? const Color(0xFF1D2242) : const Color(0xFFE0E4F3),
    surfaceContainerHighest: isDark ? const Color(0xFF252B52) : const Color(0xFFD8DDEF),
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
      margin: EdgeInsets.zero,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? const Color(0xFF11142A) : scheme.surfaceContainerLow,
      indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.28 : 0.18),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(
        theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
      thickness: 1,
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: theme.textTheme.labelLarge,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 6,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
    ),
    textTheme: theme.textTheme.copyWith(
      displayLarge: theme.textTheme.displayLarge?.copyWith(
          fontFeatures: tab, fontWeight: FontWeight.w700, letterSpacing: -2),
      displayMedium: theme.textTheme.displayMedium?.copyWith(
          fontFeatures: tab, fontWeight: FontWeight.w700, letterSpacing: -1.5),
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

/// Gradient behind hero surfaces (tuner dial, metronome pad).
LinearGradient heroGradient(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isDark
        ? const [Color(0xFF1A1E45), Color(0xFF12152E), Color(0xFF0D0F22)]
        : const [Color(0xFF2E3170), Color(0xFF3B3F8C), Color(0xFF5257B0)],
  );
}
