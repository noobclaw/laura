import 'package:flutter/material.dart';

import '../core/branding.dart';

/// Nocturnal, premium theme for a sleep app: a deep indigo night surface set,
/// flat filled cards with generous radius, and tabular figures on the number
/// styles (the app's numbers are its emotional payload). Dark by default —
/// nobody wants a bright white screen at bedtime.
ThemeData buildNightTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: Branding.seedColor,
    brightness: Brightness.dark,
  );
  final scheme = base.copyWith(
    surface: const Color(0xFF12142A),
    surfaceContainerLowest: const Color(0xFF0D0F1F),
    surfaceContainerLow: const Color(0xFF16182E),
    surfaceContainer: const Color(0xFF1A1D33),
    surfaceContainerHigh: const Color(0xFF20233B),
    surfaceContainerHighest: const Color(0xFF262A45),
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
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF12142A),
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    textTheme: theme.textTheme.copyWith(
      displayLarge: theme.textTheme.displayLarge
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      displayMedium: theme.textTheme.displayMedium
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      displaySmall: theme.textTheme.displaySmall
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      headlineMedium: theme.textTheme.headlineMedium
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      headlineSmall: theme.textTheme.headlineSmall
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      titleLarge: theme.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
    ),
  );
}
