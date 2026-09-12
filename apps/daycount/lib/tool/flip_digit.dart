import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Daybird's signature motion: a split-flap digit, the kind that clacks on an
/// old airport departures board. Each digit is two half-tiles; changing the
/// value folds the top half of the old digit down over the hinge (a real
/// `Matrix4.rotationX` with perspective), then the bottom half of the new
/// digit unfolds into place.
///
/// On first appearance the digit ratchets up from 0 through every
/// intermediate value to its target (fast steps), so a "42" visibly counts
/// itself in. Later changes — the midnight tick, an edit — do a single flip
/// straight to the new digit. Honors `MediaQuery.disableAnimations`.
///
/// The tile is sized by its caller ([FlipNumber] already folds the user's
/// text scale into [width] / [height] / [style]), so the digit itself is
/// drawn unscaled — otherwise a large system font pushed the glyph out of
/// its half-tiles.
class FlipDigit extends StatefulWidget {
  const FlipDigit({
    super.key,
    required this.digit,
    required this.style,
    required this.width,
    required this.height,
    this.tileColor = const Color(0x2E000000),
    this.delay = Duration.zero,
    this.ratchetFromZero = true,
  }) : assert(digit >= 0 && digit <= 9);

  /// The value to show, 0–9.
  final int digit;
  final TextStyle style;
  final double width;
  final double height;

  /// Background of each half-tile; a translucent dark works on any accent.
  final Color tileColor;

  /// Wait before the first ratchet starts — stagger digits for a wave.
  final Duration delay;

  /// When false the widget starts on [digit] and only animates later changes.
  final bool ratchetFromZero;

  @override
  State<FlipDigit> createState() => _FlipDigitState();
}

class _FlipDigitState extends State<FlipDigit>
    with SingleTickerProviderStateMixin {
  static const Duration _ratchetStep = Duration(milliseconds: 85);
  static const Duration _singleFlip = Duration(milliseconds: 300);

  late final AnimationController _ctrl;
  late int _shown; // digit currently at rest on the tiles
  int _next = 0; // digit folding in while animating
  bool _ratchet = false; // still counting in from zero
  bool _kicked = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _singleFlip)
      ..addStatusListener(_onStatus);
    _shown = widget.ratchetFromZero ? 0 : widget.digit;
    _ratchet = widget.ratchetFromZero;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_kicked) return;
    _kicked = true;
    if (_reduceMotion || widget.delay == Duration.zero) {
      _advance();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _advance();
      });
    }
  }

  @override
  void didUpdateWidget(FlipDigit old) {
    super.didUpdateWidget(old);
    // A change that lands mid-flip is picked up by _onStatus, which re-reads
    // widget.digit once the current flip completes.
    if (old.digit != widget.digit) _advance();
  }

  void _onStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    setState(() => _shown = _next);
    _ctrl.reset();
    _advance();
  }

  /// Take one step toward the target digit, or stop when it is reached.
  void _advance() {
    if (!mounted || _ctrl.isAnimating) return;
    final target = widget.digit;
    if (_shown == target) {
      _ratchet = false;
      return;
    }
    if (_reduceMotion) {
      setState(() {
        _shown = target;
        _ratchet = false;
      });
      return;
    }
    // setState so the resting faces (built once per flip, outside the
    // AnimatedBuilder) show the incoming digit before the flap starts.
    setState(() {
      if (_ratchet) {
        _next = (_shown + 1) % 10;
        _ctrl.duration = _ratchetStep;
      } else {
        _next = target;
        _ctrl.duration = _singleFlip;
      }
    });
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// One half of a digit tile. [shade] darkens the face (0–1) to sell the
  /// flap turning away from the light.
  Widget _face(int d, {required bool top, double shade = 0}) {
    final r = Radius.circular(widget.width * 0.18);
    return ClipRRect(
      borderRadius: top
          ? BorderRadius.vertical(top: r)
          : BorderRadius.vertical(bottom: r),
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        heightFactor: 0.5,
        child: Container(
          width: widget.width,
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.tileColor,
            gradient: shade > 0
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45 * shade),
                      Colors.black.withValues(alpha: 0.25 * shade),
                    ],
                  )
                : null,
          ),
          // The tile already accounts for the text scale; scaling the glyph
          // again would clip it against the half-tile edge.
          child: Text(
            '$d',
            style: widget.style,
            textScaler: TextScaler.noScaling,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = widget.height;
    // Resting halves: the incoming digit already waits on the top tile, the
    // outgoing digit still sits on the bottom one. Neither changes during a
    // flip, so they are built once here and handed to the AnimatedBuilder as
    // `child` instead of being rebuilt every frame.
    final resting = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          child: _face(_ctrl.isAnimating ? _next : _shown, top: true),
        ),
        Positioned(bottom: 0, left: 0, child: _face(_shown, top: false)),
      ],
    );
    // Own layer: the flap repaints 60 times a second, the card around it
    // should not.
    return RepaintBoundary(
      child: SizedBox(
        width: w,
        height: h,
        child: AnimatedBuilder(
          animation: _ctrl,
          child: resting,
          builder: (context, resting) {
            final animating = _ctrl.isAnimating;
            final t = Curves.easeInOut.transform(_ctrl.value);
            final perspective = Matrix4.identity()..setEntry(3, 2, 0.0022);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                resting!,
                // First half of the flip: old top flap folds down toward the
                // viewer around the hinge.
                if (animating && t < 0.5)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Transform(
                      alignment: Alignment.bottomCenter,
                      transform: perspective.clone()
                        ..rotateX((t / 0.5) * (math.pi / 2)),
                      child: _face(_shown, top: true, shade: t / 0.5),
                    ),
                  ),
                // Second half: new bottom flap unfolds from the hinge to rest.
                if (animating && t >= 0.5)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: Transform(
                      alignment: Alignment.topCenter,
                      transform: perspective.clone()
                        ..rotateX(-(1 - (t - 0.5) / 0.5) * (math.pi / 2)),
                      child: _face(
                        _next,
                        top: false,
                        shade: 1 - (t - 0.5) / 0.5,
                      ),
                    ),
                  ),
                // Hinge.
                Positioned(
                  left: 0,
                  right: 0,
                  top: h / 2 - 0.75,
                  child: Container(
                    height: 1.5,
                    color: Colors.black.withValues(alpha: 0.28),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A whole number rendered as a row of [FlipDigit]s, sized to fit the width
/// it is given (a five-digit anniversary shrinks rather than overflows).
/// Digits stagger their count-in by [stagger] each, left to right.
///
/// Digits are keyed by place value (units, tens, …) so a change that adds a
/// digit — 99 → 100 — keeps the existing tiles and only introduces the new
/// leading one; and once the number has been shown, digits that appear later
/// start on their value instead of counting in from zero again.
///
/// Reads to assistive tech as the whole number, not digit by digit.
class FlipNumber extends StatefulWidget {
  const FlipNumber({
    super.key,
    required this.value,
    required this.textColor,
    this.maxFontSize = 96,
    this.tileColor = const Color(0x2E000000),
    this.stagger = const Duration(milliseconds: 60),
    this.ratchetFromZero = true,
  });

  final int value;
  final Color textColor;
  final double maxFontSize;
  final Color tileColor;
  final Duration stagger;
  final bool ratchetFromZero;

  @override
  State<FlipNumber> createState() => _FlipNumberState();
}

class _FlipNumberState extends State<FlipNumber> {
  /// Set after the first frame: digits that appear later no longer ratchet.
  bool _shownOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _shownOnce = true);
  }

  @override
  Widget build(BuildContext context) {
    final digits = widget.value.abs().toString();
    final n = digits.length;
    const gap = 5.0;
    final scaler = MediaQuery.textScalerOf(context);
    final ratchet = widget.ratchetFromZero && !_shownOnce;
    return Semantics(
      label: '${widget.value}',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, c) {
          final maxW = c.maxWidth.isFinite ? c.maxWidth : double.infinity;
          // Honour the system text scale by scaling the whole tile, not just
          // the glyph; then shrink the font until every tile fits (tile width
          // is ~0.68 em).
          var fontSize = scaler.scale(widget.maxFontSize);
          if (maxW.isFinite) {
            final fit = (maxW - gap * (n - 1)) / (n * 0.68);
            if (fit < fontSize) fontSize = math.max(28, fit);
          }
          final style = TextStyle(
            fontSize: fontSize,
            height: 1.0,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: widget.textColor,
          );
          final w = fontSize * 0.68;
          final h = fontSize * 1.14;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                FlipDigit(
                  // Keyed by place value (0 = units) so a tile survives a
                  // change in digit count.
                  key: ValueKey('flip-place-${n - 1 - i}'),
                  digit: int.parse(digits[i]),
                  style: style,
                  width: w,
                  height: h,
                  tileColor: widget.tileColor,
                  delay: widget.stagger * i,
                  ratchetFromZero: ratchet,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
