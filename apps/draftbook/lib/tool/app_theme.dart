import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../core/branding.dart';

/// Draftbook's art direction: **paper and ink**.
///
/// The light theme sits on a bone-white paper (`#F6F4EE`) rather than
/// Material's neutral grey, the dark theme on an ink navy (`#0E1519`), and the
/// accent is the ink blue from [Branding.seedColor] (hue 198°). Editing
/// surfaces use `surfaceContainerLowest` — the "page" the writer types on —
/// so the manuscript is always the brightest thing on screen in light mode and
/// the calmest in dark mode.
///
/// Word counts are the app's emotional payload, so every number style gets
/// tabular figures: a count ticking up while you type must not make the line
/// jitter.
ThemeData buildDraftbookTheme(Brightness brightness) {
  final seeded = ColorScheme.fromSeed(
    seedColor: Branding.seedColor,
    brightness: brightness,
  );
  final dark = brightness == Brightness.dark;
  final scheme = dark
      ? seeded.copyWith(
          surface: const Color(0xFF0E1519),
          surfaceContainerLowest: const Color(0xFF0A1014),
          surfaceContainerLow: const Color(0xFF121B20),
          surfaceContainer: const Color(0xFF172228),
          surfaceContainerHigh: const Color(0xFF1D2A31),
          surfaceContainerHighest: const Color(0xFF24333B),
          onSurface: const Color(0xFFE7EDF0),
          onSurfaceVariant: const Color(0xFFA3B4BD),
          outlineVariant: const Color(0xFF33454E),
        )
      : seeded.copyWith(
          surface: const Color(0xFFF6F4EE),
          surfaceContainerLowest: const Color(0xFFFFFDF8),
          surfaceContainerLow: const Color(0xFFF1EEE5),
          surfaceContainer: const Color(0xFFEAE6DC),
          surfaceContainerHigh: const Color(0xFFE3DED2),
          surfaceContainerHighest: const Color(0xFFDBD5C7),
          onSurface: const Color(0xFF17222A),
          onSurfaceVariant: const Color(0xFF586873),
          outlineVariant: const Color(0xFFD5CFC1),
        );

  final theme = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    useMaterial3: true,
  );

  const tab = <FontFeature>[FontFeature.tabularFigures()];
  return theme.copyWith(
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
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
      titleTextStyle: theme.textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 6,
      highlightElevation: 2,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 10,
    ),
    textTheme: theme.textTheme.copyWith(
      displayLarge: theme.textTheme.displayLarge
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      displayMedium: theme.textTheme.displayMedium
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      displaySmall: theme.textTheme.displaySmall
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      headlineMedium: theme.textTheme.headlineMedium
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      headlineSmall: theme.textTheme.headlineSmall
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      titleLarge: theme.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      labelLarge: theme.textTheme.labelLarge?.copyWith(fontFeatures: tab),
      labelMedium: theme.textTheme.labelMedium?.copyWith(fontFeatures: tab),
    ),
  );
}
