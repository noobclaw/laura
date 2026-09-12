import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../core/branding.dart';

/// Daybird's own art direction on top of the coral brand seed: the light
/// theme sits on a warm cream (`#FFF7F2`) rather than Material's neutral
/// grey-white, the dark theme on a wine-black, so the app reads as one warm
/// object end to end instead of a coral accent on a generic surface. Flat
/// filled cards with a generous unified radius, tabular figures on the number
/// styles — the day counts are the app's emotional payload, so the digits
/// must not jitter as they tick down. Page changes use Material 3's
/// fade-forwards transition instead of the default hard slide.
ThemeData buildDayCountTheme(Brightness brightness) {
  final seeded = ColorScheme.fromSeed(
    seedColor: Branding.seedColor,
    brightness: brightness,
  );
  final dark = brightness == Brightness.dark;
  final scheme = dark
      ? seeded.copyWith(
          surface: const Color(0xFF1B1012),
          surfaceContainerLowest: const Color(0xFF150C0E),
          surfaceContainerLow: const Color(0xFF221518),
          surfaceContainer: const Color(0xFF2A1B1E),
          surfaceContainerHigh: const Color(0xFF342226),
          surfaceContainerHighest: const Color(0xFF3F2B2F),
          onSurface: const Color(0xFFF6E7E3),
          onSurfaceVariant: const Color(0xFFD5B9B5),
          outlineVariant: const Color(0xFF5A4246),
        )
      : seeded.copyWith(
          surface: const Color(0xFFFFF7F2),
          surfaceContainerLowest: const Color(0xFFFFFFFF),
          surfaceContainerLow: const Color(0xFFFCF0EA),
          surfaceContainer: const Color(0xFFF8E8E0),
          surfaceContainerHigh: const Color(0xFFF3DFD6),
          surfaceContainerHighest: const Color(0xFFEDD5CB),
          onSurface: const Color(0xFF2A1A18),
          onSurfaceVariant: const Color(0xFF6E5854),
          outlineVariant: const Color(0xFFE6CFC6),
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
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 6,
      highlightElevation: 2,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      extendedTextStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
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
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
    ),
  );
}
