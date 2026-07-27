import 'package:flutter/material.dart';

import '../core/branding.dart';

/// Remcard's calm, study-friendly theme: the teal seed, flat filled cards with
/// a generous radius, tabular figures on the number styles (due-counts are the
/// app's emotional payload, so they must not jitter), and a transparent app
/// bar. Built from a single brightness so light and dark share one shape.
ThemeData buildRemcardTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Branding.seedColor,
    brightness: brightness,
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
      backgroundColor: Colors.transparent,
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
