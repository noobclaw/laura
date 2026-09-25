import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../core/l10n.dart';

// Draftbook's design tokens (PLAN.md 设计简报). Archetype: **Editorial** — a
// typesetter's proof: white page on galley paper, near-black ink, hairline
// rules, and one "blue pencil" accent at hue 198°.
//
// This file is the ONLY place in lib/tool/ a raw colour, radius, duration or
// curve may appear (kb/UIUX规矩.md 2.2). Widgets read the named slots below:
// colours through `DbColors.of(context)`, everything else through the static
// token classes.

// ---------------------------------------------------------------------------
// Tier 1: primitives, named by what they measure. Nothing outside this file
// reads these.
// ---------------------------------------------------------------------------

abstract final class _P {
  // Light: galley paper and a white page.
  static const paper96 = Color(0xFFF7F6F2);
  static const page100 = Color(0xFFFFFFFF);
  static const paper94 = Color(0xFFF1EFEA);
  static const paper92 = Color(0xFFECE9E3);
  static const paper90 = Color(0xFFE6E3DC);
  static const paper88 = Color(0xFFE0DCD4);
  static const rule84 = Color(0xFFDAD6CC);
  static const rule56 = Color(0xFF8A877F);
  static const ink12 = Color(0xFF1B1D1E);
  static const ink40 = Color(0xFF5E6367);
  static const pencil38 = Color(0xFF175F7E); // hue 198°
  static const pencil92 = Color(0xFFDCEBF1);
  static const pencil20 = Color(0xFF0B3344);
  static const proof35 = Color(0xFFA8321F); // proofreader's red
  static const proof93 = Color(0xFFF6E3DE);
  static const proof22 = Color(0xFF5A170C);

  // Dark: warm graphite, not black, and not the navy of a blueprint.
  static const graphite09 = Color(0xFF171615);
  static const graphite12 = Color(0xFF201F1D);
  static const graphite11 = Color(0xFF1D1C1A);
  static const graphite14 = Color(0xFF232220);
  static const graphite17 = Color(0xFF2A2927);
  static const graphite20 = Color(0xFF312F2C);
  static const graphite22 = Color(0xFF34322F);
  static const graphite47 = Color(0xFF74716B);
  static const bone91 = Color(0xFFE8E6E1);
  static const bone65 = Color(0xFFA29E97);
  static const pencil74 = Color(0xFF7CBEDB); // hue 198°
  static const pencil15 = Color(0xFF0E2530);
  static const pencil26 = Color(0xFF1F3A46);
  static const pencil90 = Color(0xFFCFEAF5);
  static const proof68 = Color(0xFFF08A76);
  static const proof12 = Color(0xFF3A0E06);
  static const proof20 = Color(0xFF45211A);
  static const proof88 = Color(0xFFFFD9D0);

  static const clear = Color(0x00000000);
}

// ---------------------------------------------------------------------------
// Tier 2: semantic colour slots.
// ---------------------------------------------------------------------------

@immutable
class DbColors extends ThemeExtension<DbColors> {
  const DbColors({
    required this.paper,
    required this.page,
    required this.ink,
    required this.inkMuted,
    required this.rule,
    required this.ruleStrong,
    required this.accent,
    required this.onAccent,
    required this.accentWash,
    required this.signal,
    required this.signalWash,
    required this.onSignalWash,
  });

  /// The galley paper every screen sits on.
  final Color paper;

  /// The white page the manuscript is set on — brighter than [paper].
  final Color page;
  final Color ink;

  /// Secondary text; ≥4.5:1 on both [paper] and [page].
  final Color inkMuted;

  /// Hairline separators and the lightest gauge ticks.
  final Color rule;

  /// Control borders and ticks that must read (≥3:1).
  final Color ruleStrong;

  /// The blue pencil: primary action, caret, the gauge's ink. ≤10% of a screen.
  final Color accent;
  final Color onAccent;
  final Color accentWash;

  /// Proofreader's red: errors and destructive actions only.
  final Color signal;
  final Color signalWash;
  final Color onSignalWash;

  static const light = DbColors(
    paper: _P.paper96,
    page: _P.page100,
    ink: _P.ink12,
    inkMuted: _P.ink40,
    rule: _P.rule84,
    ruleStrong: _P.rule56,
    accent: _P.pencil38,
    onAccent: _P.page100,
    accentWash: _P.pencil92,
    signal: _P.proof35,
    signalWash: _P.proof93,
    onSignalWash: _P.proof22,
  );

  static const dark = DbColors(
    paper: _P.graphite09,
    page: _P.graphite12,
    ink: _P.bone91,
    inkMuted: _P.bone65,
    rule: _P.graphite22,
    ruleStrong: _P.graphite47,
    accent: _P.pencil74,
    onAccent: _P.pencil15,
    accentWash: _P.pencil26,
    signal: _P.proof68,
    signalWash: _P.proof20,
    onSignalWash: _P.proof88,
  );

  /// Fully transparent — the only colour a widget may name without a slot.
  static const Color clear = _P.clear;

  static DbColors of(BuildContext context) {
    final ext = Theme.of(context).extension<DbColors>();
    assert(ext != null, 'DbColors missing: build ThemeData via buildDraftbookTheme().');
    return ext!;
  }

  @override
  DbColors copyWith({
    Color? paper,
    Color? page,
    Color? ink,
    Color? inkMuted,
    Color? rule,
    Color? ruleStrong,
    Color? accent,
    Color? onAccent,
    Color? accentWash,
    Color? signal,
    Color? signalWash,
    Color? onSignalWash,
  }) =>
      DbColors(
        paper: paper ?? this.paper,
        page: page ?? this.page,
        ink: ink ?? this.ink,
        inkMuted: inkMuted ?? this.inkMuted,
        rule: rule ?? this.rule,
        ruleStrong: ruleStrong ?? this.ruleStrong,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        accentWash: accentWash ?? this.accentWash,
        signal: signal ?? this.signal,
        signalWash: signalWash ?? this.signalWash,
        onSignalWash: onSignalWash ?? this.onSignalWash,
      );

  @override
  DbColors lerp(ThemeExtension<DbColors>? other, double t) {
    if (other is! DbColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return DbColors(
      paper: l(paper, other.paper),
      page: l(page, other.page),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      rule: l(rule, other.rule),
      ruleStrong: l(ruleStrong, other.ruleStrong),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentWash: l(accentWash, other.accentWash),
      signal: l(signal, other.signal),
      signalWash: l(signalWash, other.signalWash),
      onSignalWash: l(onSignalWash, other.onSignalWash),
    );
  }
}

// ---------------------------------------------------------------------------
// Shape: three radii, and nothing else (设计简报 7).
// ---------------------------------------------------------------------------

abstract final class DbRadius {
  static const double none = 0;
  static const double small = 4;
  static const double pill = 999;

  static const BorderRadius noneAll = BorderRadius.zero;
  static const BorderRadius smallAll = BorderRadius.all(Radius.circular(small));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius sheetTop = BorderRadius.vertical(top: Radius.circular(small));

  /// Hairline width: the app separates with rules, not shadows.
  static const double hairline = 1;
}

// ---------------------------------------------------------------------------
// Space: an 8pt grid with a 4pt half step.
// ---------------------------------------------------------------------------

abstract final class DbSpace {
  static const double x0_5 = 4;
  static const double x1 = 8;
  static const double x1_5 = 12;
  static const double x2 = 16;
  static const double x2_5 = 20;
  static const double x3 = 24;
  static const double x4 = 32;
  static const double x6 = 48;

  /// Left/right margin of every screen.
  static const double gutter = 20;

  /// List rows.
  static const double row = 56;

  /// The smallest tappable edge (kb F7).
  static const double tap = 44;

  /// Icon buttons in bars.
  static const double iconButton = 48;

  /// Minimum height of a bottom bar and of a full-width button.
  static const double bar = 52;

  /// The fortnight chart in the stats sheet.
  static const double chart = 112;
}

// ---------------------------------------------------------------------------
// Motion: five durations, three curves (kb 四).
// ---------------------------------------------------------------------------

abstract final class DbMotion {
  static const Duration press = Duration(milliseconds: 120);
  static const Duration small = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration sheet = Duration(milliseconds: 400);
  static const Duration hero = Duration(milliseconds: 700);

  /// Exits run at ~0.66 of their entrance.
  static const Duration mediumExit = Duration(milliseconds: 200);

  /// How long an Undo stays on screen (kb F4: ≥5 s).
  static const Duration undoWindow = Duration(seconds: 6);

  /// Undo under a screen reader: long enough to be reached.
  static const Duration undoWindowAccessible = Duration(seconds: 30);

  /// Entrances and exits: strong ease-out.
  static const Curve enter = Cubic(0.23, 1, 0.32, 1);

  /// Movement on screen.
  static const Curve move = Cubic(0.77, 0, 0.175, 1);

  /// iOS-style panels.
  static const Curve panel = Cubic(0.32, 0.72, 0, 1);

  /// Linear, for values that track a gesture or a count.
  static const Curve linear = Curves.linear;

  /// A duration that collapses to zero under the system "reduce motion"
  /// setting (kb F12). Short fades may keep [fadeUnderReduce].
  static Duration of(BuildContext context, Duration full) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : full;

  /// Fades are allowed to survive reduced motion at ≤150 ms.
  static const Duration fadeUnderReduce = Duration(milliseconds: 150);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Every bottom sheet's entrance and exit: [sheet] in, [mediumExit] out,
  /// both zero under reduced motion (kb F12).
  static AnimationStyle sheetStyle(BuildContext context) => AnimationStyle(
        duration: of(context, sheet),
        reverseDuration: of(context, mediumExit),
      );

  /// The scale a pressed card or button settles at.
  static const double pressScale = 0.97;
}

// ---------------------------------------------------------------------------
// Type. Newsreader (OFL, bundled) carries the manuscript and the display
// moments; UI chrome stays on the system face. Chinese always falls back to
// the system (PingFang on iOS).
// ---------------------------------------------------------------------------

abstract final class DbType {
  static const String serif = 'Newsreader';
  static const String display = 'NewsreaderDisplay';

  /// Per-script fallback, ending in the platform default.
  static const List<String> fallback = [
    'PingFang SC',
    'PingFang TC',
    'Heiti SC',
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'Roboto',
  ];

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// The day's count and the book's total.
  static const TextStyle figure = TextStyle(
    fontFamily: display,
    fontFamilyFallback: fallback,
    fontSize: 46,
    height: 1.0,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.9,
    fontFeatures: tabular,
  );

  /// A book's title on its own page.
  static const TextStyle title = TextStyle(
    fontFamily: display,
    fontFamilyFallback: fallback,
    fontSize: 34,
    height: 1.12,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.6,
  );

  /// Screen titles, chapter heads, sheet heads.
  static const TextStyle heading = TextStyle(
    fontFamily: display,
    fontFamilyFallback: fallback,
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
  );

  /// Titles inside rows (a scene, a version, a book on the shelf).
  static const TextStyle rowTitle = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: fallback,
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  /// The manuscript itself, in the editor.
  static const TextStyle manuscript = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: fallback,
    fontSize: 18,
    height: 1.62,
  );

  /// A few lines of the manuscript, quoted on the home page.
  static const TextStyle excerpt = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: fallback,
    fontSize: 16,
    height: 1.6,
  );

  static const TextStyle _byline = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: fallback,
    fontSize: 16,
    height: 1.35,
  );

  static const TextStyle _bylineSmall = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: fallback,
    fontSize: 14,
    height: 1.3,
  );

  /// Bylines: chapter and scene, "of 500 words today". Italic in Latin
  /// script only: Chinese has no italic, and the system would shear PingFang
  /// into a fake one (kb 5.3 字阶「中英切换后不掉版」).
  static TextStyle get byline => italic(_byline);

  /// The chapter line under a scene title in a bar; italic as [byline].
  static TextStyle get bylineSmall => italic(_bylineSmall);

  /// Small figures: gauge numerals, per-scene counts.
  static const TextStyle numeral = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: fallback,
    fontSize: 13,
    height: 1.2,
    fontFeatures: tabular,
  );

  /// [s] set in italic when the interface is in a Latin-script language.
  static TextStyle italic(TextStyle s) =>
      s.copyWith(fontStyle: isZhLocale ? FontStyle.normal : FontStyle.italic);

  // UI text on the system face (SF on iPhone). Colour is applied at use.

  /// A sentence of context: "12,480 words in 3 chapters".
  static const TextStyle note = TextStyle(fontSize: 16, height: 1.4, fontFeatures: tabular, fontFamilyFallback: fallback);

  /// Row metadata: counts and times.
  static const TextStyle meta = TextStyle(fontSize: 14, height: 1.35, fontFeatures: tabular, fontFamilyFallback: fallback);

  /// A short emphatic line (a banner headline, a row label).
  static const TextStyle strong = TextStyle(fontSize: 16, height: 1.3, fontWeight: FontWeight.w600, fontFamilyFallback: fallback);

  /// Body copy in sheets and dialogs.
  static const TextStyle body = TextStyle(fontSize: 16, height: 1.45, fontFamilyFallback: fallback);

  /// Typographic buttons in the editor bar (B, I, H).
  static const TextStyle glyph = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: fallback,
    fontSize: 20,
    height: 1,
    fontWeight: FontWeight.w600,
  );
}

// ---------------------------------------------------------------------------
// ThemeData
// ---------------------------------------------------------------------------

ColorScheme _scheme(Brightness b) => b == Brightness.dark
    ? const ColorScheme(
        brightness: Brightness.dark,
        primary: _P.pencil74,
        onPrimary: _P.pencil15,
        primaryContainer: _P.pencil26,
        onPrimaryContainer: _P.pencil90,
        secondary: _P.bone65,
        onSecondary: _P.graphite09,
        secondaryContainer: _P.graphite17,
        onSecondaryContainer: _P.bone91,
        tertiary: _P.bone91,
        onTertiary: _P.graphite09,
        error: _P.proof68,
        onError: _P.proof12,
        errorContainer: _P.proof20,
        onErrorContainer: _P.proof88,
        surface: _P.graphite09,
        onSurface: _P.bone91,
        onSurfaceVariant: _P.bone65,
        surfaceContainerLowest: _P.graphite12,
        surfaceContainerLow: _P.graphite11,
        surfaceContainer: _P.graphite14,
        surfaceContainerHigh: _P.graphite17,
        surfaceContainerHighest: _P.graphite20,
        outline: _P.graphite47,
        outlineVariant: _P.graphite22,
        inverseSurface: _P.bone91,
        onInverseSurface: _P.graphite09,
        inversePrimary: _P.pencil38,
        shadow: _P.graphite09,
        scrim: _P.graphite09,
        surfaceTint: _P.clear,
      )
    : const ColorScheme(
        brightness: Brightness.light,
        primary: _P.pencil38,
        onPrimary: _P.page100,
        primaryContainer: _P.pencil92,
        onPrimaryContainer: _P.pencil20,
        secondary: _P.ink40,
        onSecondary: _P.page100,
        secondaryContainer: _P.paper90,
        onSecondaryContainer: _P.ink12,
        tertiary: _P.ink12,
        onTertiary: _P.page100,
        error: _P.proof35,
        onError: _P.page100,
        errorContainer: _P.proof93,
        onErrorContainer: _P.proof22,
        surface: _P.paper96,
        onSurface: _P.ink12,
        onSurfaceVariant: _P.ink40,
        surfaceContainerLowest: _P.page100,
        surfaceContainerLow: _P.paper94,
        surfaceContainer: _P.paper92,
        surfaceContainerHigh: _P.paper90,
        surfaceContainerHighest: _P.paper88,
        outline: _P.rule56,
        outlineVariant: _P.rule84,
        inverseSurface: _P.ink12,
        onInverseSurface: _P.paper96,
        inversePrimary: _P.pencil74,
        shadow: _P.ink12,
        scrim: _P.ink12,
        surfaceTint: _P.clear,
      );

/// [uiFontFamily] is for the screenshot harness only; on device the UI text
/// is the platform face (SF on iPhone).
ThemeData buildDraftbookTheme(Brightness brightness, {String? uiFontFamily}) {
  final cs = _scheme(brightness);
  final c = brightness == Brightness.dark ? DbColors.dark : DbColors.light;
  final base = ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    scaffoldBackgroundColor: c.paper,
    splashFactory: NoSplash.splashFactory,
    highlightColor: DbColors.clear,
    splashColor: DbColors.clear,
  );
  const tab = DbType.tabular;
  final t = base.textTheme;
  final buttonText = TextStyle(
    fontFamily: uiFontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    fontFamilyFallback: DbType.fallback,
  );
  const shortSide = Size(DbSpace.tap, DbSpace.tap);

  return base.copyWith(
    extensions: [c],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.24),
      selectionHandleColor: c.accent,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper,
      foregroundColor: c.ink,
      surfaceTintColor: DbColors.clear,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: DbType.heading.copyWith(color: c.ink),
      shape: Border(bottom: BorderSide(color: c.rule, width: DbRadius.hairline)),
    ),
    dividerTheme: DividerThemeData(color: c.rule, space: DbRadius.hairline, thickness: DbRadius.hairline),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(DbSpace.tap, DbSpace.bar),
        padding: const EdgeInsets.symmetric(horizontal: DbSpace.x3, vertical: DbSpace.x1_5),
        shape: const RoundedRectangleBorder(borderRadius: DbRadius.smallAll),
        textStyle: buttonText,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(DbSpace.tap, DbSpace.bar),
        padding: const EdgeInsets.symmetric(horizontal: DbSpace.x2_5, vertical: DbSpace.x1_5),
        side: BorderSide(color: c.ruleStrong, width: DbRadius.hairline),
        shape: const RoundedRectangleBorder(borderRadius: DbRadius.smallAll),
        textStyle: buttonText,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        minimumSize: shortSide,
        shape: const RoundedRectangleBorder(borderRadius: DbRadius.smallAll),
        textStyle: buttonText,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(DbSpace.iconButton, DbSpace.iconButton),
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.page,
      modalBackgroundColor: c.page,
      surfaceTintColor: DbColors.clear,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: c.ruleStrong,
      shape: const RoundedRectangleBorder(borderRadius: DbRadius.sheetTop),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.page,
      surfaceTintColor: DbColors.clear,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: DbRadius.smallAll,
        side: BorderSide(color: c.rule, width: DbRadius.hairline),
      ),
      titleTextStyle: DbType.heading.copyWith(color: c.ink),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: cs.inverseSurface,
      contentTextStyle: DbType.note.copyWith(color: cs.onInverseSurface, fontFamily: uiFontFamily),
      actionTextColor: cs.inversePrimary,
      shape: const RoundedRectangleBorder(borderRadius: DbRadius.smallAll),
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: UnderlineInputBorder(borderSide: BorderSide(color: c.ruleStrong)),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.ruleStrong)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.accent, width: 2)),
      labelStyle: TextStyle(color: c.inkMuted),
      floatingLabelStyle: TextStyle(color: c.accent),
      hintStyle: TextStyle(color: c.inkMuted),
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: c.ruleStrong, width: DbRadius.hairline)),
      backgroundColor: c.page,
      selectedColor: c.accentWash,
      checkmarkColor: c.accent,
      labelStyle: DbType.note.copyWith(color: c.ink, fontFamily: uiFontFamily),
      side: BorderSide(color: c.ruleStrong, width: DbRadius.hairline),
      padding: const EdgeInsets.symmetric(horizontal: DbSpace.x1, vertical: DbSpace.x1),
    ),
    listTileTheme: ListTileThemeData(
      minTileHeight: DbSpace.row,
      minVerticalPadding: DbSpace.x1,
      iconColor: c.inkMuted,
      textColor: c.ink,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.page,
      surfaceTintColor: DbColors.clear,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: DbRadius.smallAll,
        side: BorderSide(color: c.rule, width: DbRadius.hairline),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStatePropertyAll(c.ruleStrong),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.rule,
      ),
    ),
    textTheme: t.apply(fontFamilyFallback: DbType.fallback).copyWith(
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: t.labelLarge?.copyWith(fontFeatures: tab),
      labelMedium: t.labelMedium?.copyWith(fontFeatures: tab),
      labelSmall: t.labelSmall?.copyWith(fontFeatures: tab),
      bodySmall: t.bodySmall?.copyWith(height: 1.45),
    ),
  );
}
