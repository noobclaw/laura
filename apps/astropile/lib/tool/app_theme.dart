import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// AstroPile's art direction on top of the shell's premium base theme.
///
/// The subject is a dark sky, so the app leans nocturnal in both brightness
/// modes: deep indigo surfaces, a periwinkle accent that survives on near
/// black, generous radii, and numerals that read like instrument readouts
/// (star counts, residuals in pixels — the numbers *are* the product here).
ThemeData buildAstroTheme(Brightness brightness) {
  final base = buildAppTheme(brightness);
  final cs = base.colorScheme;
  final dark = brightness == Brightness.dark;
  return base.copyWith(
    scaffoldBackgroundColor: dark ? const Color(0xFF0B0E1A) : cs.surface,
    colorScheme: dark
        ? cs.copyWith(
            surface: const Color(0xFF0B0E1A),
            surfaceContainerHigh: const Color(0xFF171B2E),
            surfaceContainerHighest: const Color(0xFF1F2440),
          )
        : cs,
    cardTheme: base.cardTheme.copyWith(
      color: dark ? const Color(0xFF171B2E) : cs.surfaceContainerHigh,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: dark ? const Color(0xFF0B0E1A) : cs.surface,
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

/// The night-sky gradient used by the hero and the progress ring backdrop.
const List<Color> kSkyGradient = [Color(0xFF141A3A), Color(0xFF2C1E52), Color(0xFF0C1030)];

/// Status accents. Semantic, and readable on both the light card and the
/// dark hero.
class AstroColors {
  static const ok = Color(0xFF4ADE80);
  static const warn = Color(0xFFFBBF24);
  static const bad = Color(0xFFF87171);
  static const reference = Color(0xFF8B9BFF);
}
