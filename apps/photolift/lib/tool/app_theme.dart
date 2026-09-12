import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../core/branding.dart';

/// Gold: the "lifted" accent — result badges, the resolved pixels in the
/// hero, the light band on the progress ring. Never used for actions.
const Color kLiftGold = Color(0xFFFFC857);

/// Deep wine: the dark end of the hero gradient and the dark-mode ground.
const Color kLiftWine = Color(0xFF3A0F22);

/// PhotoLift's theme: a rose Material 3 scheme on a warm-white ground (light)
/// or a wine-black ground (dark), flat rounded cards, pill buttons, tabular
/// figures on the size / time read-outs and Material 3 page transitions.
ThemeData buildPhotoLiftTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final seeded = ColorScheme.fromSeed(
    seedColor: Branding.seedColor,
    brightness: brightness,
  );
  // Warm-white / wine-black surface ramp instead of the neutral tonal one:
  // the photos are sepia and the accent is rose, a grey ground fights both.
  final scheme = dark
      ? seeded.copyWith(
          surface: const Color(0xFF1A0E13),
          surfaceContainerLowest: const Color(0xFF12090D),
          surfaceContainerLow: const Color(0xFF221419),
          surfaceContainer: const Color(0xFF29181E),
          surfaceContainerHigh: const Color(0xFF322026),
          surfaceContainerHighest: const Color(0xFF3C2830),
          onSurface: const Color(0xFFF6E8EC),
          onSurfaceVariant: const Color(0xFFD3B9C2),
          outlineVariant: const Color(0xFF5A3F48),
          primary: const Color(0xFFFF8FB5),
          onPrimary: const Color(0xFF4E0F2A),
          primaryContainer: const Color(0xFF7A2148),
          onPrimaryContainer: const Color(0xFFFFD9E4),
        )
      : seeded.copyWith(
          surface: const Color(0xFFFFF8F7),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFFBF1F2),
          surfaceContainer: const Color(0xFFF7EAEC),
          surfaceContainerHigh: const Color(0xFFF2E2E5),
          surfaceContainerHighest: const Color(0xFFECD9DD),
          onSurface: const Color(0xFF2A1219),
          onSurfaceVariant: const Color(0xFF6E5059),
          outlineVariant: const Color(0xFFE2C9D0),
          primary: const Color(0xFFB8204F),
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFFFD9E3),
          onPrimaryContainer: const Color(0xFF400016),
        );
  final theme = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    useMaterial3: true,
  );

  const tab = <FontFeature>[FontFeature.tabularFigures()];
  return theme.copyWith(
    // Shared-axis-ish forward transition on Android, the platform default
    // zoom elsewhere — nothing hard-cuts (PIPELINE 视觉设计标准 #10 ④).
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      TargetPlatform.linux: ZoomPageTransitionsBuilder(),
      TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
    }),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    textTheme: theme.textTheme.copyWith(
      displaySmall: theme.textTheme.displaySmall
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      headlineMedium: theme.textTheme.headlineMedium
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      headlineSmall: theme.textTheme.headlineSmall
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      titleLarge: theme.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      labelLarge: theme.textTheme.labelLarge?.copyWith(fontFeatures: tab),
    ),
  );
}

/// The hero gradient: rose into deep wine, top-left to bottom-right. Fixed
/// (not scheme-derived) so the hero reads the same in light and dark and
/// white / gold type always sits on it.
LinearGradient heroGradient(ColorScheme cs) => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFE0407A), Color(0xFF8E1F4C), kLiftWine],
      stops: [0.0, 0.55, 1.0],
    );
