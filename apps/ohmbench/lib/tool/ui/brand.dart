import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'lab_theme.dart';

/// OhmBench's mark: a resistor trace that draws itself in, then carries a
/// pulse of charge across it forever. The same drawing as the launcher icon,
/// so the app bar and the home screen icon read as one thing.
class OhmMark extends StatefulWidget {
  const OhmMark({super.key, this.size = 30});

  final double size;

  @override
  State<OhmMark> createState() => _OhmMarkState();
}

class _OhmMarkState extends State<OhmMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
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
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size(widget.size * 1.45, widget.size),
          painter: _MarkPainter(_c.value,
              still: MediaQuery.of(context).disableAnimations),
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
    final drawn = still ? 1.0 : Curves.easeOutCubic.transform((t / 0.35).clamp(0, 1));
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
        ..color = Bench.positive.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke),
    );
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
      canvas.drawCircle(
          p,
          r * 2.4,
          Paint()
            ..color = Bench.charge.withValues(alpha: 0.4)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.4));
      canvas.drawCircle(p, r, Paint()..color = Bench.charge);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.t != t;
}

/// "OhmBench" set as a wordmark: the weight change marks the join, the way
/// a part number reads on a component.
class OhmWordmark extends StatelessWidget {
  const OhmWordmark({super.key, this.size = 21});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: 'Ohm',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            color: Bench.ink,
            letterSpacing: -0.4,
          ),
        ),
        TextSpan(
          text: 'Bench',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w400,
            color: Bench.inkDim,
            letterSpacing: -0.2,
          ),
        ),
      ]),
    );
  }
}

/// A slow drift of faint charge across a panel: used behind the paywall and
/// the settings header so the bench keeps living everywhere, quietly.
class ChargeField extends StatefulWidget {
  const ChargeField({super.key, this.count = 14});

  final int count;

  @override
  State<ChargeField> createState() => _ChargeFieldState();
}

class _ChargeFieldState extends State<ChargeField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 9));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
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
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) =>
              CustomPaint(painter: _FieldPainter(_c.value, widget.count)),
        ),
      );
}

class _FieldPainter extends CustomPainter {
  _FieldPainter(this.t, this.count);

  final double t;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    // Horizontal "traces" at fixed heights, each with one moving charge.
    final rnd = math.Random(7);
    final line = Paint()
      ..color = Bench.gridMajor
      ..strokeWidth = 1;
    for (var i = 0; i < count; i++) {
      final y = size.height * (i + 0.5) / count;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      final speed = 0.6 + rnd.nextDouble() * 0.9;
      final offset = rnd.nextDouble();
      final x = ((t * speed + offset) % 1.0) * size.width;
      canvas.drawCircle(
          Offset(x, y),
          5,
          Paint()
            ..color = Bench.charge.withValues(alpha: 0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(Offset(x, y), 1.6,
          Paint()..color = Bench.charge.withValues(alpha: 0.55));
    }
  }

  @override
  bool shouldRepaint(covariant _FieldPainter old) => old.t != t;
}
