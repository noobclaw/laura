import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../core/branding.dart';

/// The app's fixed accents, on top of the seeded scheme.
abstract final class NightPalette {
  /// Deep plum-black night surface — the ground everything sits on.
  static const Color night = Color(0xFF14091C);
  static const Color nightLowest = Color(0xFF0C0512);
  static const Color nightLow = Color(0xFF1A0C24);
  static const Color nightMid = Color(0xFF21102D);
  static const Color nightHigh = Color(0xFF2A1638);
  static const Color nightHighest = Color(0xFF341C45);

  /// Moon yellow — used for exactly one emphasis per screen (the mic core,
  /// the score needle tip, the loudest bar label).
  static const Color moon = Color(0xFFFFD166);

  /// Plum ramp for gradients that must stay in the seed's hue band.
  static const Color plum = Color(0xFF8E24AA);
  static const Color plumDeep = Color(0xFF4A148C);
  static const Color plumLight = Color(0xFFCE93D8);
}

/// Nocturnal, premium theme for a sleep app: a deep plum-black night surface
/// set, flat filled cards with generous radius, and tabular figures on the
/// number styles (the app's numbers are its emotional payload). Dark by
/// default — nobody wants a bright white screen at bedtime.
ThemeData buildNightTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: Branding.seedColor,
    brightness: Brightness.dark,
  );
  final scheme = base.copyWith(
    surface: NightPalette.night,
    surfaceContainerLowest: NightPalette.nightLowest,
    surfaceContainerLow: NightPalette.nightLow,
    surfaceContainer: NightPalette.nightMid,
    surfaceContainerHigh: NightPalette.nightHigh,
    surfaceContainerHighest: NightPalette.nightHighest,
    tertiary: NightPalette.moon,
    onTertiary: NightPalette.nightLowest,
  );

  final theme = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    useMaterial3: true,
  );

  const tab = <FontFeature>[FontFeature.tabularFigures()];
  return theme.copyWith(
    // Material 3 forward-fade between routes instead of the default hard
    // slide; iOS keeps its native swipe-back transition.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: NightPalette.night,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w700),
      titleLarge: theme.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
    ),
  );
}

/// True when the platform asks for reduced motion — every looping or
/// decorative animation in the app checks this and holds still.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
