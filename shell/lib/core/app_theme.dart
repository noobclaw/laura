import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'branding.dart';

/// The shell's default premium theme, so every new app starts at the G6b visual
/// bar instead of bare `ColorScheme.fromSeed` (PIPELINE.md「视觉设计标准」).
/// Built from [Branding.seedColor] — set that per app and this carries the rest:
/// flat filled cards with a generous radius, and tabular figures + weight on the
/// number styles (a tool's numbers are its emotional payload). Works for both
/// light and dark via [brightness].
///
/// This is a floor, not a look: every app replaces it with its own tokens
/// (hand-authored light/dark colors, a bundled display font, three radii,
/// motion durations) per the design brief in kb/UIUX规矩.md. Shipping this
/// theme unchanged is what made the catalog look alike.
ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Branding.seedColor,
    brightness: brightness,
  );
  final theme = ThemeData(colorScheme: scheme, useMaterial3: true);

  const tab = <FontFeature>[FontFeature.tabularFigures()];
  return theme.copyWith(
    // Android fades forward (no hard cuts, PIPELINE 视觉标准 10). iOS keeps
    // the native Cupertino slide: it is what carries the edge-swipe-back
    // gesture, and a fade there silently removed it (kb/UIUX规矩.md, 09-25).
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: const AppBarTheme(
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
