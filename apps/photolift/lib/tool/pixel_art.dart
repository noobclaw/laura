import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The app's signature graphic: an 8×8 mosaic that "resolves" block by
/// block from the top-left corner to the bottom-right — each coarse block
/// dissolving into a 4×4 grid of finer pixels with real detail in them.
/// A photo going from blurry to sharp, drawn rather than shown.
///
/// Two ways to drive it:
///  * [progress] set → the mosaic is resolved up to that fraction (0 = all
///    coarse, 1 = all fine). Used inside the progress ring.
///  * [progress] null → loops on its own: 3 s to resolve, 2 s hold, then a
///    quick dissolve back. Used on the home hero. Honours
///    `MediaQuery.disableAnimations` by showing the fully-resolved frame.
class PixelResolve extends StatefulWidget {
  const PixelResolve({
    super.key,
    this.progress,
    this.grid = 8,
    this.gap = 2,
    this.radius = 3,
    this.opacity = 1,
  });

  final double? progress;
  final int grid;
  final double gap;
  final double radius;
  final double opacity;

  @override
  State<PixelResolve> createState() => _PixelResolveState();
}

class _PixelResolveState extends State<PixelResolve>
    with SingleTickerProviderStateMixin {
  // 3 s resolve + 2 s hold (the hold ends with a 0.4 s dissolve back).
  static const _cycle = Duration(milliseconds: 5000);
  // Created eagerly in initState: a lazy `late final` here would be first
  // touched by dispose() on the fixed-progress variant (which never reads it
  // in build) and creating a Ticker from a deactivated element asserts.
  late final AnimationController _loop;

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(vsync: this, duration: _cycle);
  }

  // Start / stop from didChangeDependencies (and didUpdateWidget), not from
  // build: the loop must resume when "reduce motion" is switched off again,
  // and MediaQuery changes only arrive as a dependency change.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoop();
  }

  @override
  void didUpdateWidget(PixelResolve old) {
    super.didUpdateWidget(old);
    _syncLoop();
  }

  void _syncLoop() {
    final shouldRun =
        widget.progress == null && !MediaQuery.disableAnimationsOf(context);
    if (shouldRun && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!shouldRun && _loop.isAnimating) {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  /// Loop value → resolve fraction: 0–0.6 resolving, 0.6–0.92 held at
  /// full detail, 0.92–1.0 dissolving back so the restart is not a hard cut.
  static double _loopToResolve(double v) {
    if (v < 0.6) return v / 0.6;
    if (v < 0.92) return 1;
    return 1 - (v - 0.92) / 0.08;
  }

  @override
  Widget build(BuildContext context) {
    final fixed = widget.progress;
    if (fixed != null) {
      return CustomPaint(
        painter: PixelResolvePainter(
          resolve: fixed.clamp(0.0, 1.0),
          grid: widget.grid,
          gap: widget.gap,
          radius: widget.radius,
          opacity: widget.opacity,
        ),
      );
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      return CustomPaint(
        painter: PixelResolvePainter(
          resolve: 1,
          grid: widget.grid,
          gap: widget.gap,
          radius: widget.radius,
          opacity: widget.opacity,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) => CustomPaint(
        painter: PixelResolvePainter(
          resolve: _loopToResolve(_loop.value),
          grid: widget.grid,
          gap: widget.gap,
          radius: widget.radius,
          opacity: widget.opacity,
        ),
      ),
    );
  }
}

/// Paints the mosaic. Colours come from a deterministic "image": a rose→gold
/// field along the diagonal, with a high-frequency ripple that only the fine
/// pixels sample — so a resolved block is visibly more detailed (and a touch
/// brighter) than the flat coarse block it replaces. No randomness: the same
/// frame always looks the same, which keeps the loop calm.
class PixelResolvePainter extends CustomPainter {
  const PixelResolvePainter({
    required this.resolve,
    this.grid = 8,
    this.gap = 2,
    this.radius = 3,
    this.opacity = 1,
  });

  final double resolve;
  final int grid;
  final double gap;
  final double radius;
  final double opacity;

  static const int _sub = 4;
  static const Color _rose = Color(0xFFE0407A);
  static const Color _roseLight = Color(0xFFFF6E9C);
  static const Color _gold = kLiftGold;
  static const Color _cream = Color(0xFFFFF1F4);
  static const Color _wine = kLiftWine;

  /// Colour of the underlying picture at (x, y) in [0, 1]².
  static Color _field(double x, double y, {required bool fine}) {
    final d = ((x + y) / 2).clamp(0.0, 1.0);
    // Rose on the top-left, gold towards the bottom-right, with a lighter
    // band through the middle so the diagonal reads as a highlight.
    final base = d < 0.5
        ? Color.lerp(_rose, _roseLight, d * 2)!
        : Color.lerp(_roseLight, _gold, (d - 0.5) * 2)!;
    if (!fine) {
      // Coarse blocks are the "blurry" picture: flatter and a little muddier.
      return Color.lerp(base, _wine, 0.28)!;
    }
    final ripple = math.sin(x * 23.0) * math.cos(y * 17.0);
    final sparkle = math.sin(x * 41.0 + y * 29.0);
    var c = ripple >= 0
        ? Color.lerp(base, _cream, ripple * 0.55)!
        : Color.lerp(base, _wine, -ripple * 0.5)!;
    if (sparkle > 0.86) c = Color.lerp(c, Colors.white, 0.75)!;
    return c;
  }

  /// The picture only depends on [grid], so its colours are sampled once per
  /// grid size and reused by every frame: paint() used to run ~1k
  /// Color.lerp + trig calls per frame, which the progress ring repainted
  /// while the CPU-only engine was busy.
  static final Map<int, _PixelPalette> _palettes = {};

  static _PixelPalette _paletteFor(int n) => _palettes.putIfAbsent(n, () {
        final coarse = List<Color>.filled(n * n, _rose);
        final fine = List<Color>.filled(n * n * _sub * _sub, _rose);
        for (var r = 0; r < n; r++) {
          for (var c = 0; c < n; c++) {
            coarse[r * n + c] = _field((c + 0.5) / n, (r + 0.5) / n, fine: false);
            for (var sr = 0; sr < _sub; sr++) {
              for (var sc = 0; sc < _sub; sc++) {
                fine[((r * n + c) * _sub + sr) * _sub + sc] = _field(
                    (c + (sc + 0.5) / _sub) / n, (r + (sr + 0.5) / _sub) / n,
                    fine: true);
              }
            }
          }
        }
        return _PixelPalette(coarse, fine);
      });

  @override
  void paint(Canvas canvas, Size size) {
    final n = grid;
    final cell = (math.min(size.width, size.height) - gap * (n - 1)) / n;
    if (cell <= 0) return;
    final ox = (size.width - (cell * n + gap * (n - 1))) / 2;
    final oy = (size.height - (cell * n + gap * (n - 1))) / 2;
    final paint = Paint();
    final maxDiag = 2 * (n - 1);
    // Each block resolves over a window 0.22 wide, staggered along the
    // diagonal so the whole sweep finishes exactly at resolve == 1.
    const window = 0.22;
    final subCell = (cell - gap * 0.5 * (_sub - 1)) / _sub;
    final subGap = gap * 0.5;
    final palette = _paletteFor(n);

    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final start = (r + c) / maxDiag * (1 - window);
        final u = ((resolve - start) / window).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(u);
        final x = ox + c * (cell + gap);
        final y = oy + r * (cell + gap);
        final rect = Rect.fromLTWH(x, y, cell, cell);
        final block = r * n + c;

        if (eased < 1) {
          paint.color =
              palette.coarse[block].withValues(alpha: (1 - eased) * opacity);
          canvas.drawRRect(
              RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
        }
        if (eased > 0) {
          for (var sr = 0; sr < _sub; sr++) {
            for (var sc = 0; sc < _sub; sc++) {
              // Sub-pixels fade in with a tiny stagger of their own so the
              // block "sharpens" rather than pops.
              final lag = (sr + sc) / (2 * (_sub - 1)) * 0.35;
              final a = ((eased - lag) / (1 - lag)).clamp(0.0, 1.0);
              if (a <= 0) continue;
              paint.color = palette.fine[(block * _sub + sr) * _sub + sc]
                  .withValues(alpha: a * opacity);
              final sx = x + sc * (subCell + subGap);
              final sy = y + sr * (subCell + subGap);
              canvas.drawRRect(
                RRect.fromRectAndRadius(
                    Rect.fromLTWH(sx, sy, subCell, subCell),
                    Radius.circular(radius * 0.4)),
                paint,
              );
            }
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(PixelResolvePainter old) =>
      old.resolve != resolve ||
      old.grid != grid ||
      old.gap != gap ||
      old.radius != radius ||
      old.opacity != opacity;
}

class _PixelPalette {
  const _PixelPalette(this.coarse, this.fine);
  /// One colour per block, row-major.
  final List<Color> coarse;
  /// `_sub × _sub` colours per block, row-major within the block.
  final List<Color> fine;
}

/// Progress ring with a light band sweeping along the filled arc. The band
/// is a narrow white sweep-gradient rotated by [sweep] (0–1, one lap; a
/// negative value draws no band) and clipped to the filled portion by
/// drawing it with the same arc.
class LiftRingPainter extends CustomPainter {
  const LiftRingPainter({
    required this.fraction,
    required this.sweep,
    required this.track,
    this.stroke = 14,
  });

  final double fraction;
  final double sweep;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, trackPaint);
    final f = fraction.clamp(0.0, 1.0);
    if (f <= 0) return;
    final arc = math.pi * 2 * f;
    final fill = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFFE0407A), Color(0xFFFF6E9C), kLiftGold],
        stops: [0.0, 0.55, 1.0],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, -math.pi / 2, arc, false, fill);
    if (sweep < 0) return; // reduced motion: no band
    // The light band: transparent → white → transparent over ~40°, rotated
    // around the ring by [sweep]; clamp tiling keeps the rest transparent.
    final band = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.5, 1.0],
        startAngle: 0,
        endAngle: 0.7,
        transform: GradientRotation(-math.pi / 2 + sweep * math.pi * 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, -math.pi / 2, arc, false, band);
  }

  @override
  bool shouldRepaint(LiftRingPainter old) =>
      old.fraction != fraction ||
      old.sweep != sweep ||
      old.track != track ||
      old.stroke != stroke;
}

/// Press feedback for a hero action: scales down to 0.96 while the pointer
/// is down, springs back on release. Wrap any tappable; the child keeps its
/// own onTap — this only listens.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down && widget.enabled && !reduce ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
