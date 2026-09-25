import 'package:flutter/material.dart';

import 'lab_theme.dart';

/// OhmBench's mark: a resistor trace, with a pulse of charge crossing it.
/// The same drawing as the launcher icon, so the wordmark and the home
/// screen icon read as one thing.
///
/// Static by default. With [animate] it draws itself in and carries a loop
/// of charge — only where no other ambient scene is on screen (the Pro
/// sheet), and never under "reduce motion".
class OhmMark extends StatefulWidget {
  const OhmMark({super.key, this.size = 30, this.animate = false});

  final double size;
  final bool animate;

  @override
  State<OhmMark> createState() => _OhmMarkState();
}

class _OhmMarkState extends State<OhmMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: BenchMotion.markLoop);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loop = widget.animate &&
        !BenchMotion.reduced(context) &&
        TickerMode.valuesOf(context).enabled;
    if (!loop) {
      _c.value = 1;
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = !widget.animate || BenchMotion.reduced(context);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            size: Size(widget.size * 1.45, widget.size),
            painter: _MarkPainter(_c.value, still: still),
          ),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.t, {required this.still});

  final double t;
  final bool still;

  List<Offset> _points(Size s) {
    final y = s.height / 2;
    final w = s.width;
    final pts = <Offset>[Offset(0, y), Offset(w * 0.26, y)];
    const peaks = 4;
    for (var i = 0; i < peaks; i++) {
      final x = w * (0.26 + (i + 0.5) * 0.48 / peaks);
      pts.add(Offset(x, y + (i.isEven ? -1 : 1) * s.height * 0.34));
    }
    pts
      ..add(Offset(w * 0.74, y))
      ..add(Offset(w, y));
    return pts;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = _points(size);
    final lengths = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      lengths.add(lengths.last + (pts[i] - pts[i - 1]).distance);
    }
    final total = lengths.last;

    Offset at(double d) {
      for (var i = 1; i < pts.length; i++) {
        if (d <= lengths[i]) {
          final u = (d - lengths[i - 1]) / (lengths[i] - lengths[i - 1]);
          return Offset.lerp(pts[i - 1], pts[i], u)!;
        }
      }
      return pts.last;
    }

    // 0..0.35 draw in, then hold; the charge pulse loops the whole time.
    final drawn =
        still ? 1.0 : BenchMotion.enter.transform((t / 0.35).clamp(0, 1));
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      if (lengths[i] <= total * drawn) {
        path.lineTo(pts[i].dx, pts[i].dy);
      } else {
        final end = at(total * drawn);
        path.lineTo(end.dx, end.dy);
        break;
      }
    }
    final stroke = size.height * 0.12;
    canvas.drawPath(
      path,
      Paint()
        ..color = Bench.positive
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (drawn >= 1) {
      final phase = still ? 0.5 : (t * 1.6) % 1.0;
      final p = at(total * phase);
      final r = size.height * 0.13;
      canvas.drawCircle(p, r, Paint()..color = Bench.charge);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) =>
      old.t != t || old.still != still;
}

/// "OhmBench" as a wordmark in Martian Mono: the weight change marks the
/// join, the way a part number reads on a component.
class OhmWordmark extends StatelessWidget {
  const OhmWordmark({super.key, this.size = BenchType.display});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Ohm', style: BenchType.monoStyle(size, bold: true)),
        TextSpan(
            text: 'Bench',
            style: BenchType.monoStyle(size, color: Bench.inkDim)),
      ]),
      // The mark is a logo: it may cap its own growth at 1.5× (F10).
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5),
    );
  }
}

/// Anything pressable on the bench: shrinks to 0.97 the instant a finger
/// lands (not on release), springs back on the same curve, and carries its
/// own button semantics. Minimum 44 × 44 (F7).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.child,
    this.label,
    this.onLongPress,
    this.minSize = BenchSpace.row,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  /// Semantic label; null when [child] already reads well on its own.
  final String? label;
  final double minSize;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? BenchMotion.pressScale : 1,
          duration: BenchMotion.of(context, BenchMotion.press),
          curve: BenchMotion.enter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minWidth: widget.minSize, minHeight: widget.minSize),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The bench's own drawn glyphs for its core controls — same stroke and
/// caps as the canvas, so run/stop/wire read as part of the drawing, not a
/// borrowed icon set.
enum GlyphKind { play, stop, wire }

class BenchGlyph extends StatelessWidget {
  const BenchGlyph(this.kind,
      {super.key, this.size = 20, this.color = Bench.ink});

  final GlyphKind kind;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size),
          painter: _GlyphPainter(kind, color),
        ),
      );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind, this.color);

  final GlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()..color = color;
    switch (kind) {
      case GlyphKind.play:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.22, h * 0.12)
            ..lineTo(w * 0.88, h * 0.5)
            ..lineTo(w * 0.22, h * 0.88)
            ..close(),
          fill,
        );
      case GlyphKind.stop:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(w * 0.2, h * 0.2, w * 0.8, h * 0.8),
            BenchRadius.smRadius,
          ),
          fill,
        );
      case GlyphKind.wire:
        // Two pins joined by an L-routed wire: what wire mode draws.
        final stroke = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.1
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.18, h * 0.3)
            ..lineTo(w * 0.62, h * 0.3)
            ..lineTo(w * 0.62, h * 0.78),
          stroke,
        );
        canvas.drawCircle(Offset(w * 0.18, h * 0.3), w * 0.12, fill);
        canvas.drawCircle(Offset(w * 0.62, h * 0.78), w * 0.12, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.kind != kind || old.color != color;
}
