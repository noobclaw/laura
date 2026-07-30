import 'package:flutter/material.dart';

import '../core/branding.dart';

/// Per-app theme for 回声笔记. A calm, tactile take on Material 3 built from the
/// app's own teal seed: flat filled cards with generous radius, a quiet flat
/// app bar, and tabular figures + a touch more weight on the number/heading
/// styles (durations and the live timer are the app's emotional payload).
/// Both brightnesses are tuned so light and dark feel equally considered.
ThemeData buildEchoJotTheme(Brightness brightness) {
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
      // One content inset across the app (search field, banners, cards, panel):
      // misaligned left edges are what makes a screen look assembled, not designed.
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
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
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w600),
      titleLarge: theme.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      labelLarge: theme.textTheme.labelLarge
          ?.copyWith(fontFeatures: tab),
      bodySmall: theme.textTheme.bodySmall?.copyWith(fontFeatures: tab),
    ),
  );
}
