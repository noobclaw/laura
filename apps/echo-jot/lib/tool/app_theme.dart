import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../core/branding.dart';

/// EchoJot's own colours beyond the Material scheme. Kept as a ThemeExtension
/// so every screen reads the same "we are listening" mint instead of guessing.
///
/// Art direction (2026-09-12): violet seed (258°), lavender-tinted surfaces in
/// light mode, ink-purple surfaces in dark mode, and a single mint accent that
/// means exactly one thing — a live microphone.
@immutable
class EchoJotColors extends ThemeExtension<EchoJotColors> {
  const EchoJotColors({
    required this.live,
    required this.onLive,
    required this.liveText,
    required this.fieldIdle,
    required this.fieldGlow,
  });

  /// Mint used for the sound field bars, the pulse ring and the live button.
  final Color live;

  /// Glyph colour on top of [live].
  final Color onLive;

  /// A darker/lighter mint that passes contrast as text on the surface.
  final Color liveText;

  /// Resting colour of the sound-field bars while nothing is recording.
  final Color fieldIdle;

  /// Soft radial glow behind the mic while a session is live.
  final Color fieldGlow;

  static const _mint = Color(0xFF5EF2C1);

  // Light mode uses a deeper mint: the neon tone reads on ink surfaces but is
  // ~1.1:1 against the lavender panel. #1FB98F clears 3:1 for the bars and
  // button, #0B6E55 clears 4.5:1 for the timer text, and the idle bars sit at
  // #8F76E6 (≥3:1) instead of a near-invisible pastel.
  static const light = EchoJotColors(
    live: Color(0xFF1FB98F),
    onLive: Color(0xFF07241B),
    liveText: Color(0xFF0B6E55),
    fieldIdle: Color(0xFF8F76E6),
    fieldGlow: Color(0x331FB98F),
  );

  static const dark = EchoJotColors(
    live: _mint,
    onLive: Color(0xFF07241B),
    liveText: _mint,
    fieldIdle: Color(0xFF5E4C9A),
    fieldGlow: Color(0x2E5EF2C1),
  );

  static EchoJotColors of(BuildContext context) =>
      Theme.of(context).extension<EchoJotColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  EchoJotColors copyWith({
    Color? live,
    Color? onLive,
    Color? liveText,
    Color? fieldIdle,
    Color? fieldGlow,
  }) =>
      EchoJotColors(
        live: live ?? this.live,
        onLive: onLive ?? this.onLive,
        liveText: liveText ?? this.liveText,
        fieldIdle: fieldIdle ?? this.fieldIdle,
        fieldGlow: fieldGlow ?? this.fieldGlow,
      );

  @override
  EchoJotColors lerp(EchoJotColors? other, double t) {
    if (other == null) return this;
    return EchoJotColors(
      live: Color.lerp(live, other.live, t)!,
      onLive: Color.lerp(onLive, other.onLive, t)!,
      liveText: Color.lerp(liveText, other.liveText, t)!,
      fieldIdle: Color.lerp(fieldIdle, other.fieldIdle, t)!,
      fieldGlow: Color.lerp(fieldGlow, other.fieldGlow, t)!,
    );
  }
}

/// Per-app theme for 回声笔记. Material 3 from the violet seed, with the
/// neutral surfaces pushed towards lavender (light) / ink purple (dark) so the
/// app never reads as "grey Material with a purple button". Tabular figures
/// and extra weight on the number/heading styles: durations and the live timer
/// are the app's emotional payload.
ThemeData buildEchoJotTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final seeded = ColorScheme.fromSeed(
    seedColor: Branding.seedColor,
    brightness: brightness,
  );
  // fromSeed keeps its neutrals close to grey; the lavender / ink-purple
  // surface ladder is what makes the screen unmistakably this app.
  final scheme = dark
      ? seeded.copyWith(
          surface: const Color(0xFF15111F),
          surfaceContainerLowest: const Color(0xFF0F0B18),
          surfaceContainerLow: const Color(0xFF1C1729),
          surfaceContainer: const Color(0xFF221C32),
          surfaceContainerHigh: const Color(0xFF29223C),
          surfaceContainerHighest: const Color(0xFF332B48),
          onSurface: const Color(0xFFEAE3FF),
          onSurfaceVariant: const Color(0xFFC6BBE0),
          outlineVariant: const Color(0xFF4A4060),
          primary: const Color(0xFFCDBDFF),
          onPrimary: const Color(0xFF2E1A6E),
        )
      : seeded.copyWith(
          surface: const Color(0xFFFBF9FF),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF4F0FF),
          surfaceContainer: const Color(0xFFEFE9FE),
          surfaceContainerHigh: const Color(0xFFE9E2FB),
          surfaceContainerHighest: const Color(0xFFE2DAF7),
          onSurface: const Color(0xFF1B1530),
          onSurfaceVariant: const Color(0xFF574C72),
          outlineVariant: const Color(0xFFD5CBEC),
          primary: const Color(0xFF6A3DF0),
          onPrimary: Colors.white,
        );

  final theme = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    useMaterial3: true,
  );

  const tab = <FontFeature>[FontFeature.tabularFigures()];
  return theme.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      dark ? EchoJotColors.dark : EchoJotColors.light,
    ],
    // Shared-axis-style fade for every route push; iOS keeps its native
    // edge-swipe transition (users expect the back gesture to work).
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
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
      // One content inset across the app (search field, banners, cards, panel):
      // misaligned left edges are what makes a screen look assembled, not designed.
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
    ),
    chipTheme: theme.chipTheme.copyWith(
      backgroundColor: scheme.surfaceContainerLowest,
      side: BorderSide(color: scheme.outlineVariant),
      shape: const StadiumBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
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
          ?.copyWith(fontFeatures: tab, fontWeight: FontWeight.w600),
      titleLarge: theme.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      labelLarge: theme.textTheme.labelLarge
          ?.copyWith(fontFeatures: tab),
      bodySmall: theme.textTheme.bodySmall?.copyWith(fontFeatures: tab),
    ),
  );
}
