import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// PicWorks art direction on top of the shell's premium base theme.
///
/// Palette: a lime seed (Branding.seedColor, hue ~88°) with **cream**
/// surfaces in light mode and **charcoal** surfaces in dark mode — a
/// workbench, not a darkroom. Controls: slightly tighter card radius for the
/// dense option panels, filled tonal inputs, pill segmented buttons. Page
/// transitions use Material 3's fade-forwards instead of the platform default
/// hard cut (PIPELINE 视觉设计标准 #10 ④).
ThemeData buildPicboxTheme(Brightness brightness) {
  final base = buildAppTheme(brightness);
  final dark = brightness == Brightness.dark;
  // Tonal surfaces re-tinted toward cream / charcoal. The seed-derived
  // surfaces are grey-green; these keep the lime warmth without the murk.
  final cs = base.colorScheme.copyWith(
    surface: dark ? const Color(0xFF141613) : const Color(0xFFFAFAF2),
    surfaceContainerLowest: dark ? const Color(0xFF0E100D) : const Color(0xFFFFFFFF),
    surfaceContainerLow: dark ? const Color(0xFF1B1E19) : const Color(0xFFF4F5EA),
    surfaceContainer: dark ? const Color(0xFF20241E) : const Color(0xFFEEF0E3),
    surfaceContainerHigh: dark ? const Color(0xFF2A2F27) : const Color(0xFFE8EBDB),
    surfaceContainerHighest: dark ? const Color(0xFF343A30) : const Color(0xFFE1E5D3),
    onSurface: dark ? const Color(0xFFE6E8E0) : const Color(0xFF1B1D17),
    onSurfaceVariant: dark ? const Color(0xFFB8BDAD) : const Color(0xFF4F5548),
    outlineVariant: dark ? const Color(0xFF3F4639) : const Color(0xFFCBD1BE),
  );
  return base.copyWith(
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    cardTheme: base.cardTheme.copyWith(color: cs.surfaceContainerHigh),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
      },
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide.none,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20),
    ),
  );
}

/// Accent colours for the six tools — one "toolbox" set: lime leads, with
/// orange, blue-grey and violet as the secondaries, all at a matched
/// saturation so the board reads as one family rather than six random
/// Material primaries. Each sits on cream and charcoal alike.
class ToolColors {
  static const compress = Color(0xFF7CB342); // lime — the brand tool
  static const resize = Color(0xFF4F8FB8); // sky blue-grey
  static const convert = Color(0xFF8C6BC4); // violet
  static const crop = Color(0xFFE6883A); // orange
  static const metadata = Color(0xFF5E7C99); // slate
  static const watermark = Color(0xFFCFA33C); // amber
}

/// Standard motion durations (PIPELINE #10: 150–300 ms, standard easing).
abstract final class Motion {
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const count = Duration(milliseconds: 900);

  /// Zero when the OS asks for reduced motion, else [d].
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}
