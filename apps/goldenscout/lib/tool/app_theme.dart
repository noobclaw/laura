import 'package:flutter/material.dart';

import '../core/branding.dart';

/// The dusk accent palette — GoldenScout's signature warm sky, distilled to
/// three named colors so the amber/rose/indigo that used to be sprinkled as raw
/// hex across the widgets now pulls from one place.
///
/// These are deliberately fixed brand accents (a gorgeous golden-hour sun is a
/// specific amber, not "whatever the seed resolves to"), while the surfaces and
/// text styles below come from [ColorScheme.fromSeed] so light and dark both
/// stay coherent.
const Color kDuskIndigo = Color(0xFF3A2E5C); // deep pre-dawn / post-dusk sky
const Color kDuskRose = Color(0xFFD86B4A); // horizon glow, sunset direction
const Color kGoldenAmber = Color(0xFFF5A623); // the sun itself (== the seed)

/// A warm, premium theme built from the amber seed: golden-hour amber primary,
/// a dusk-rose secondary and blue-hour indigo tertiary, flat filled cards with
/// generous radius, and tabular figures on the number styles (this app's times
/// are its emotional payload — they must never jitter). Both brightnesses are
/// tuned by hand: a warm paper light mode, a deep dusk-indigo dark mode.
ThemeData buildGoldenScoutTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: Branding.seedColor,
    brightness: brightness,
  );

  final scheme = base.copyWith(
    secondary: kDuskRose,
    onSecondary: Colors.white,
    tertiary: kDuskIndigo,
    onTertiary: Colors.white,
    // Surfaces: warm cream by day, deep dusk indigo by night.
    surface: isDark ? const Color(0xFF16131F) : const Color(0xFFFDF8F2),
    surfaceContainerLowest:
        isDark ? const Color(0xFF110E18) : const Color(0xFFFFFFFF),
    surfaceContainerLow:
        isDark ? const Color(0xFF1B1726) : const Color(0xFFFBF3EA),
    surfaceContainer:
        isDark ? const Color(0xFF201B2D) : const Color(0xFFF6EDE1),
    surfaceContainerHigh:
        isDark ? const Color(0xFF272134) : const Color(0xFFF1E7D9),
    surfaceContainerHighest:
        isDark ? const Color(0xFF2F273F) : const Color(0xFFECE0D0),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
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
