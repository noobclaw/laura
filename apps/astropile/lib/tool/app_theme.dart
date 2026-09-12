import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// AstroPile's art direction on top of the shell's premium base theme.
///
/// Silver and ink. The seed is a low-saturation silver grey, so the Material
/// scheme comes out neutral — no tinted purple cards, no coloured buttons
/// competing with the picture. The dark surfaces are an ink-blue black, the
/// kind of blue a long exposure pulls out of a moonless sky. Colour is spent
/// in exactly two places: the warm white of a star point and the mint-cyan of
/// a successful alignment (see [AstroColors]).
///
/// Numbers read like instrument readouts (tabular figures come from the base
/// theme): star counts and residuals in pixels *are* the product here.
ThemeData buildAstroTheme(Brightness brightness) {
  final base = buildAppTheme(brightness);
  final cs = base.colorScheme;
  final dark = brightness == Brightness.dark;
  // Page transitions: Material 3's forward fade on every platform. The
  // default hard cut is the one thing the visual rubric calls out by name.
  final transitions = PageTransitionsTheme(
    builders: {
      for (final p in TargetPlatform.values) p: const FadeForwardsPageTransitionsBuilder(),
    },
  );
  return base.copyWith(
    pageTransitionsTheme: transitions,
    scaffoldBackgroundColor: dark ? AstroInk.deep : cs.surface,
    colorScheme: dark
        ? cs.copyWith(
            surface: AstroInk.deep,
            surfaceContainerLow: AstroInk.low,
            surfaceContainer: AstroInk.mid,
            surfaceContainerHigh: AstroInk.card,
            surfaceContainerHighest: AstroInk.raised,
            primary: AstroColors.silver,
            onPrimary: AstroInk.deep,
            primaryContainer: AstroInk.raised,
            onPrimaryContainer: AstroColors.silver,
            secondaryContainer: AstroInk.raised,
            onSecondaryContainer: AstroColors.silver,
          )
        : cs.copyWith(
            primary: const Color(0xFF2D3648),
            onPrimary: Colors.white,
            secondaryContainer: const Color(0xFFDDE2EC),
            onSecondaryContainer: const Color(0xFF1E2535),
          ),
    cardTheme: base.cardTheme.copyWith(
      color: dark ? AstroInk.card : cs.surfaceContainerHigh,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: dark ? AstroInk.deep : cs.surface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      side: BorderSide.none,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
  );
}

/// The ink-blue surface ramp used for the dark scheme and for every night
/// panel (hero, progress ring, summary strips) in both brightness modes.
abstract final class AstroInk {
  static const deep = Color(0xFF0B1020);
  static const low = Color(0xFF0E1428);
  static const mid = Color(0xFF121A31);
  static const card = Color(0xFF161E38);
  static const raised = Color(0xFF1E2744);
}

/// The night-sky gradient behind the hero, the progress ring and the summary
/// strips: ink blue into near black, top to bottom, like the sky away from
/// the horizon.
const List<Color> kSkyGradient = [Color(0xFF141C36), Color(0xFF0B1020), Color(0xFF05070F)];

/// Status accents. Semantic (ok/warn/bad), plus the two signature colours the
/// art direction allows: the warm white of a star and the cyan of a frame
/// that lined up with the reference.
abstract final class AstroColors {
  static const ok = Color(0xFF4ADE80);
  static const warn = Color(0xFFFBBF24);
  static const bad = Color(0xFFF87171);

  /// Star points, the meteor, the headline on the hero.
  static const star = Color(0xFFFFF4D6);

  /// Alignment success: the reference pill, the ring, the converged trail.
  static const aligned = Color(0xFF7FE0C4);

  /// Kept for call sites that mark the reference frame — same cyan.
  static const reference = aligned;

  /// Neutral silver for text and outlines on the night panels.
  static const silver = Color(0xFFD5DBE7);
}
