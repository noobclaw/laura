import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// PicWorks art direction on top of the shell's premium base theme: a teal
/// seed (Branding.seedColor), slightly tighter card radius for the dense
/// tool grid, filled tonal inputs, and pill segmented buttons — the image
/// tools are option-heavy, so controls must read as one family.
ThemeData buildPicboxTheme(Brightness brightness) {
  final base = buildAppTheme(brightness);
  final cs = base.colorScheme;
  return base.copyWith(
    scaffoldBackgroundColor: cs.surface,
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

/// Accent colours for the six tool cards. Each tool has one hue so the grid
/// reads as a set of distinct instruments rather than six identical tiles;
/// all are tuned to sit on tonal surfaces in both light and dark mode.
class ToolColors {
  static const compress = Color(0xFF1E88E5);
  static const resize = Color(0xFF00897B);
  static const convert = Color(0xFF8E24AA);
  static const crop = Color(0xFFF4511E);
  static const metadata = Color(0xFF3949AB);
  static const watermark = Color(0xFFC0A000);
}
