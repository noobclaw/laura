import 'package:flutter/material.dart';

import '../core/branding.dart';

/// TuneBench's art direction: a walnut workbench with one warm meter.
///
/// The palette is low-saturation warm brown around a 20° hue — the wood of a
/// guitar back, not a stage light. Surfaces are rice paper in the light theme
/// and ebony in the dark one (the app's home: a music stand at night). Three
/// fixed accents carry meaning everywhere: amber = the needle, the beat and
/// attention; green = in tune / correct; coral = flat-or-sharp / wrong.
const Color kInTuneGreen = Color(0xFF3DDC97);
const Color kBeatAmber = Color(0xFFFFB454);
const Color kOffCoral = Color(0xFFFF6B7A);

/// Ebony: the dark scaffold. Warm black, never blue-black.
const Color kInkDark = Color(0xFF14100D);

/// Rice paper: the light scaffold.
const Color kPaper = Color(0xFFF7F1E8);

/// Walnut tones used by the hero gradients and the gauge face.
const Color kWalnutLight = Color(0xFF8D6E63);
const Color kWalnutMid = Color(0xFF5D4037);
const Color kWalnutDeep = Color(0xFF3E2723);
const Color kWalnutEbony = Color(0xFF231A16);

/// Ink on amber (buttons, root dots).
const Color kOnAmber = Color(0xFF2A1B00);

ThemeData buildTuneTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: Branding.seedColor,
    brightness: brightness,
  );

  final scheme = base.copyWith(
    primary: isDark ? const Color(0xFFD7B8A9) : kWalnutMid,
    onPrimary: isDark ? kWalnutDeep : Colors.white,
    primaryContainer: isDark ? kWalnutMid : const Color(0xFFEBD9CF),
    onPrimaryContainer: isDark ? const Color(0xFFF6E5DC) : kWalnutDeep,
    secondary: isDark ? const Color(0xFFC9B3A6) : const Color(0xFF6F5A50),
    tertiary: kBeatAmber,
    onTertiary: kOnAmber,
    tertiaryContainer: isDark ? const Color(0xFF5A3F12) : const Color(0xFFFFE2B8),
    onTertiaryContainer: isDark ? const Color(0xFFFFE2B8) : const Color(0xFF3A2600),
    surface: isDark ? kInkDark : kPaper,
    onSurface: isDark ? const Color(0xFFF1E9E1) : const Color(0xFF2B211C),
    onSurfaceVariant: isDark ? const Color(0xFFB9ABA2) : const Color(0xFF6B5D55),
    outline: isDark ? const Color(0xFF8A7B72) : const Color(0xFF8C7C72),
    outlineVariant: isDark ? const Color(0xFF4A3F39) : const Color(0xFFD6CBC1),
    surfaceContainerLowest: isDark ? const Color(0xFF0D0A08) : Colors.white,
    surfaceContainerLow: isDark ? const Color(0xFF1B1613) : const Color(0xFFF1EAE0),
    surfaceContainer: isDark ? const Color(0xFF221C18) : const Color(0xFFEBE3D8),
    surfaceContainerHigh: isDark ? const Color(0xFF2A2320) : const Color(0xFFE5DCD0),
    surfaceContainerHighest: isDark ? const Color(0xFF342C27) : const Color(0xFFDDD3C6),
  );

  final theme = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    useMaterial3: true,
  );

  const tab = <FontFeature>[FontFeature.tabularFigures()];
  return theme.copyWith(
    // Material 3 forward-fade between pushed pages instead of the hard
    // slide-up; a zoom on Android tablets / desktop feels closer to native.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
      },
    ),
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
      backgroundColor: isDark ? const Color(0xFF1B1613) : scheme.surfaceContainerLow,
      indicatorColor: kBeatAmber.withValues(alpha: isDark ? 0.28 : 0.32),
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

/// Gradient behind hero surfaces (tuner dial, metronome pad): a slab of
/// walnut, lit from the top-left. Both themes stay dark here so the amber
/// needle and the green band read the same way day and night.
LinearGradient heroGradient(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isDark
        ? const [Color(0xFF4A3129), Color(0xFF2E1F19), kWalnutEbony]
        : const [Color(0xFF7A5A4C), kWalnutMid, kWalnutDeep],
  );
}

/// Standard motion for the app: short, standard easing, and off entirely
/// when the OS asks for reduced motion.
const Duration kMotionShort = Duration(milliseconds: 180);
const Duration kMotionMedium = Duration(milliseconds: 260);
const Duration kMotionLong = Duration(milliseconds: 420);

bool motionEnabled(BuildContext context) =>
    !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
