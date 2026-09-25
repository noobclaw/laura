import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// OhmBench's design tokens. This file is the ONLY place a raw colour,
/// corner radius, font family, animation duration or easing curve may be
/// written (kb/UIUX规矩.md 2.2); every widget and painter reads the named
/// slots below. Design brief: PLAN.md §十·五.
///
/// The bench is dark-only on purpose: the canvas is a scope screen whose
/// colours ARE data (voltage → cyan/magenta, current → glowing charge), an
/// encoding that only reads on a dark board. See the brief for the reasons.
abstract final class Bench {
  // --- the board ------------------------------------------------------------
  static const Color background = Color(0xFF0A1016);
  static const Color backgroundTop = Color(0xFF0E1A23);
  static const Color gridDot = Color(0xFF1E2E3A);
  static const Color gridMajor = Color(0xFF16232D);

  // --- ink ------------------------------------------------------------------
  static const Color ink = Color(0xFFE4EDF2);
  static const Color inkDim = Color(0xFF8FA3B0);
  static const Color wireIdle = Color(0xFF9DB2C0);
  static const Color neutral = Color(0xFF5E707C);

  // --- surfaces -------------------------------------------------------------
  static const Color panel = Color(0xFF111C25);
  static const Color panelRaised = Color(0xFF142430);
  static const Color sheet = Color(0xFF0D161D);
  static const Color panelBorder = Color(0xFF223340);
  static const Color outline = Color(0xFF2E4452);
  static const Color handle = Color(0xFF3A5363);

  /// Transparent version of [background], for fades into the board.
  static const Color backgroundClear = Color(0x000A1016);

  // --- data colours (canvas + scope) ----------------------------------------
  /// Positive voltage, the scope-trace cyan.
  static const Color positive = Color(0xFF3FD4F7);

  /// Negative voltage.
  static const Color negative = Color(0xFFFF5C93);

  /// Moving charge — and the one action colour of the chrome.
  static const Color charge = Color(0xFFFFD66B);
  static const Color onCharge = Color(0xFF2B2100);
  static const Color selection = Color(0xFF3FD4F7);

  /// A latched tool's fill (wire mode on).
  static const Color secondaryFill = Color(0xFF0E3444);

  // --- scope screen ---------------------------------------------------------
  static const Color scopeGlass = Color(0xFF0F1F29);
  static const Color scopeGlassEdge = Color(0xFF081016);
  static const Color scopeGrid = Color(0xFF1C3140);
  static const Color scopeAxis = Color(0xFF2A4658);

  // --- semantic (kept apart from the brand yellow) --------------------------
  static const Color warning = Color(0xFFFFB454);
  static const Color error = Color(0xFFFF6B6B);
  static const Color onError = Color(0xFF2A0A0E);
  static const Color errorContainer = Color(0xFF3A1519);
  static const Color onErrorContainer = Color(0xFFFFD9DC);

  /// Drop shadow under floating bench chrome (never a coloured glow).
  static const Color shadow = Color(0x59000000);

  /// A voltage as a colour: grey at 0 V, cyan towards the run's highest
  /// voltage, magenta towards its most negative.
  static Color forVoltage(double volts, double peak) {
    if (peak <= 0 || !volts.isFinite) return neutral;
    final t = (volts / peak).clamp(-1.0, 1.0);
    // A gentle curve so a 1 V node in a 12 V circuit is visibly tinted.
    final k = BenchMotion.voltageRamp.transform(t.abs());
    return Color.lerp(neutral, t >= 0 ? positive : negative, k)!;
  }
}

/// The three corner radii the app uses — nothing else (brief §7).
abstract final class BenchRadius {
  static const double none = 0;
  static const double sm = 4;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius sheetTop =
      BorderRadius.vertical(top: Radius.circular(sm));
  static const Radius smRadius = Radius.circular(sm);
}

/// 4 pt base grid; 44 pt rows (instrument/blueprint density).
abstract final class BenchSpace {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double row = 44;
  static const double hairline = 1;
}

/// Type: Martian Mono (bundled, OFL) for the lettering of measurement —
/// wordmark, readouts, values, part labels, section titles; the system face
/// for reading. Four sizes, no more on any one screen.
abstract final class BenchType {
  static const String mono = 'MartianMono';

  /// Scripts and symbols Martian Mono does not carry (CJK, Ω).
  static const List<String> fallback = [
    'PingFang SC',
    'Heiti SC',
    'Noto Sans CJK SC',
    'Roboto',
  ];

  static const double display = 22;
  static const double title = 17;
  static const double body = 14;
  static const double label = 12;

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Mono lettering at [size]; [bold] for display weight.
  static TextStyle monoStyle(double size,
          {bool bold = false, Color color = Bench.ink, double? height}) =>
      TextStyle(
        fontFamily: mono,
        fontFamilyFallback: fallback,
        fontSize: size,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        color: color,
        height: height,
        letterSpacing: size >= display ? -0.6 : -0.2,
        fontFeatures: tabular,
      );

  static TextStyle bodyStyle(
          {Color color = Bench.ink,
          double size = body,
          FontWeight weight = FontWeight.w400,
          double height = 1.4}) =>
      TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        height: height,
        fontFeatures: tabular,
      );
}

/// Motion tokens (kb/UIUX规矩.md 第四节). Every animation reads one of these
/// through [of], which collapses to zero under "reduce motion".
abstract final class BenchMotion {
  static const Duration press = Duration(milliseconds: 120);
  static const Duration small = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration sheet = Duration(milliseconds: 400);
  static const Duration hero = Duration(milliseconds: 600);

  /// Exits run at ~0.7 of their entrance.
  static Duration exit(Duration d) =>
      Duration(microseconds: (d.inMicroseconds * 0.7).round());

  /// Strong ease-out: things arriving or leaving.
  static const Curve enter = Cubic(0.23, 1, 0.32, 1);

  /// Things moving on screen.
  static const Curve move = Cubic(0.77, 0, 0.175, 1);

  /// iOS-style sheets and panels.
  static const Curve panel = Cubic(0.32, 0.72, 0, 1);

  /// Not motion: how a voltage maps to colour intensity (see [Bench]).
  static const Curve voltageRamp = Cubic(0.215, 0.61, 0.355, 1.0);

  /// Ambient loops. Each one stops off-screen and under reduce motion.
  static const Duration markLoop = Duration(milliseconds: 2600);

  /// Real seconds a whole preview run takes to play back on the library.
  static const double previewPlaySeconds = 5;

  /// Real seconds a whole run takes to play back in the editor.
  static const double editorPlaySeconds = 4;

  /// Press feedback scale (emil: 0.95–0.98).
  static const double pressScale = 0.97;

  /// Snackbar with an Undo stays at least this long (F4).
  static const Duration undoWindow = Duration(seconds: 6);

  /// [d], or zero when the system asks for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

/// The one theme OhmBench ships: the whole app is the bench.
///
/// The colour scheme is written out role by role (not `fromSeed`), so no
/// Material widget can pick up a seed-derived colour nobody chose.
ThemeData buildOhmTheme([Brightness _ = Brightness.dark]) {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Bench.charge,
    onPrimary: Bench.onCharge,
    primaryContainer: Color(0xFF3A3108),
    onPrimaryContainer: Color(0xFFFFE9A8),
    secondary: Bench.positive,
    onSecondary: Color(0xFF00202B),
    secondaryContainer: Color(0xFF0E3444),
    onSecondaryContainer: Color(0xFFBDEFFF),
    tertiary: Bench.negative,
    onTertiary: Color(0xFF3A0017),
    error: Bench.error,
    onError: Bench.onError,
    errorContainer: Bench.errorContainer,
    onErrorContainer: Bench.onErrorContainer,
    surface: Bench.background,
    onSurface: Bench.ink,
    onSurfaceVariant: Bench.inkDim,
    surfaceContainerLowest: Color(0xFF070C11),
    surfaceContainerLow: Bench.sheet,
    surfaceContainer: Bench.panel,
    surfaceContainerHigh: Bench.panelRaised,
    surfaceContainerHighest: Color(0xFF1B2E3B),
    surfaceTint: Colors.transparent,
    outline: Bench.outline,
    outlineVariant: Bench.panelBorder,
    shadow: Bench.shadow,
    scrim: Bench.shadow,
    inverseSurface: Bench.ink,
    onInverseSurface: Bench.background,
    inversePrimary: Color(0xFF6E5A00),
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    // No Material ripples on an iPhone app: presses scale instead (4.1).
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
  );
  const sm = RoundedRectangleBorder(borderRadius: BenchRadius.smAll);
  final text = base.textTheme;
  // Button labels keep the platform face (SF / Roboto) from the typography.
  TextStyle? button(FontWeight w) => text.labelLarge?.copyWith(
      fontSize: BenchType.body,
      fontWeight: w,
      fontFamilyFallback: BenchType.fallback);
  final mono = TextStyle(
    fontFamily: BenchType.mono,
    fontFamilyFallback: BenchType.fallback,
    fontFeatures: BenchType.tabular,
  );

  return base.copyWith(
    scaffoldBackgroundColor: Bench.background,
    canvasColor: Bench.background,
    // iOS keeps the Cupertino push so the edge swipe back works (F9).
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS:
          _BenchPageTransitions(CupertinoPageTransitionsBuilder()),
      TargetPlatform.android:
          _BenchPageTransitions(FadeForwardsPageTransitionsBuilder()),
    }),
    textTheme: text.copyWith(
      // Display lettering: Martian Mono. Reading text: the system face.
      headlineSmall: text.headlineSmall?.merge(mono).copyWith(
          fontSize: BenchType.display,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6),
      titleLarge: text.titleLarge?.merge(mono).copyWith(
          fontSize: BenchType.title,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3),
      titleMedium: text.titleMedium
          ?.copyWith(fontSize: BenchType.title, fontWeight: FontWeight.w600),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: BenchType.title),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: BenchType.body),
      bodySmall: text.bodySmall
          ?.copyWith(fontSize: BenchType.label, color: Bench.inkDim),
      labelLarge: text.labelLarge
          ?.copyWith(fontSize: BenchType.body, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Bench.background,
      foregroundColor: Bench.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      shape: Border(bottom: BorderSide(color: Bench.panelBorder)),
    ),
    cardTheme: const CardThemeData(
      color: Bench.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BenchRadius.smAll,
        side: BorderSide(color: Bench.panelBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: sm,
        minimumSize: const Size(BenchSpace.row, BenchSpace.row),
        textStyle: button(FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: button(FontWeight.w600),
        shape: sm,
        minimumSize: const Size(BenchSpace.row, BenchSpace.row),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: sm,
        minimumSize: const Size(BenchSpace.row, BenchSpace.row),
        side: const BorderSide(color: Bench.outline),
        foregroundColor: Bench.ink,
        textStyle: button(FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: sm,
        minimumSize: const Size(BenchSpace.row, BenchSpace.row),
      ),
    ),
    chipTheme: const ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: Bench.outline)),
      backgroundColor: Bench.panel,
      labelStyle: TextStyle(color: Bench.ink, fontSize: BenchType.body),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BenchRadius.smAll),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Bench.panelRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BenchRadius.smAll,
        side: BorderSide(color: Bench.panelBorder),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Bench.sheet,
      modalBackgroundColor: Bench.sheet,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: Bench.handle,
      shape: RoundedRectangleBorder(
        borderRadius: BenchRadius.sheetTop,
        side: BorderSide(color: Bench.panelBorder),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Bench.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BenchRadius.smAll,
        side: BorderSide(color: Bench.panelBorder),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xFF1B2E3B),
      contentTextStyle: TextStyle(color: Bench.ink, fontSize: BenchType.body),
      actionTextColor: Bench.charge,
      shape: RoundedRectangleBorder(borderRadius: BenchRadius.smAll),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: Bench.panelRaised,
        borderRadius: BenchRadius.smAll,
      ),
      textStyle: TextStyle(color: Bench.ink, fontSize: BenchType.label),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Bench.onCharge : Bench.inkDim),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Bench.charge : Bench.panelRaised),
    ),
    dividerTheme: const DividerThemeData(
        color: Bench.panelBorder, thickness: BenchSpace.hairline, space: 1),
  );
}

/// The platform push, except under "reduce motion": then the slide becomes
/// a cross-fade driven by the route's own [animation] (forward it completes
/// in the first half of the 300 ms route, so ≤150 ms). The Cupertino builder
/// still wraps the page, and its edge-swipe detector drives that same route
/// controller, so a back swipe still tracks the finger — as a fade.
class _BenchPageTransitions extends PageTransitionsBuilder {
  const _BenchPageTransitions(this.platform);

  final PageTransitionsBuilder platform;

  static const Curve _quickFade = Interval(0, 0.5, curve: BenchMotion.enter);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!MediaQuery.disableAnimationsOf(context)) {
      return platform.buildTransitions(
          route, context, animation, secondaryAnimation, child);
    }
    return FadeTransition(
      opacity: CurvedAnimation(
          parent: animation, curve: _quickFade, reverseCurve: Curves.linear),
      child: platform.buildTransitions(route, context, kAlwaysCompleteAnimation,
          kAlwaysDismissedAnimation, child),
    );
  }
}
