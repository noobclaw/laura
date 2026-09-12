import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_theme.dart';

/// The app's signature graphic: a self-drawn patch of night sky.
///
/// A fixed-seed scatter of star points, each twinkling on its own phase, a
/// meteor every 6–10 s, and two or three faint star-trail arcs around a pole
/// off the top-right corner. [converge] pulls the arcs in: at 0 they are the
/// long trails a static camera records, at 1 they have collapsed into a
/// single point — which is what alignment does to a burst. The run screen
/// drives it with the overall progress; the result strip sits at 1.
///
/// One ticker, one painter, wrapped in a [RepaintBoundary] so nothing else on
/// the page repaints with it. Honours `MediaQuery.disableAnimations`: with
/// it set the field paints once and stays still.
class StarField extends StatefulWidget {
  const StarField({
    super.key,
    this.converge = 0,
    this.seed = 7,
    this.density = 1,
    this.trails = 3,
  });

  /// 0 = full star trails, 1 = trails collapsed to one aligned point.
  final double converge;

  /// Seed for the star layout, so a given panel looks the same every time.
  final int seed;

  /// Star count multiplier (1 ≈ 90 stars on a phone-wide panel).
  final double density;

  /// Number of trail arcs (0 to draw none).
  final int trails;

  @override
  State<StarField> createState() => _StarFieldState();
}

class _StarFieldState extends State<StarField> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  bool _still = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => _time.value = elapsed.inMicroseconds / 1e6);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still != _still || !_ticker.isActive && !still) {
      _still = still;
      if (still) {
        _ticker.stop();
        _time.value = 0;
      } else if (!_ticker.isActive) {
        _ticker.start();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        isComplex: true,
        painter: StarFieldPainter(
          time: _time,
          converge: widget.converge.clamp(0.0, 1.0),
          seed: widget.seed,
          density: widget.density,
          trails: widget.trails,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _Star {
  const _Star(this.x, this.y, this.r, this.base, this.phase, this.speed, this.warm);
  final double x, y; // normalised 0..1
  final double r; // px
  final double base; // resting alpha
  final double phase, speed; // twinkle
  final bool warm;
}

class _Meteor {
  const _Meteor(this.start, this.x, this.y, this.angle, this.length);
  final double start; // seconds into the schedule
  final double x, y; // head origin, normalised
  final double angle; // radians, travel direction
  final double length; // fraction of width
}

class StarFieldPainter extends CustomPainter {
  StarFieldPainter({
    required this.time,
    required this.converge,
    required this.seed,
    required this.density,
    required this.trails,
  })  : _stars = _layoutStars(seed, density),
        _meteors = _scheduleMeteors(seed),
        super(repaint: time);

  final ValueNotifier<double> time;
  final double converge;
  final int seed;
  final double density;
  final int trails;

  final List<_Star> _stars;
  final List<_Meteor> _meteors;

  static const _meteorSeconds = 0.9;

  static List<_Star> _layoutStars(int seed, double density) {
    final rnd = math.Random(seed);
    final n = (90 * density).round();
    return [
      for (var i = 0; i < n; i++)
        _Star(
          rnd.nextDouble(),
          rnd.nextDouble(),
          0.5 + rnd.nextDouble() * (rnd.nextDouble() < 0.12 ? 1.6 : 0.8),
          0.35 + rnd.nextDouble() * 0.55,
          rnd.nextDouble() * math.pi * 2,
          0.6 + rnd.nextDouble() * 1.6,
          rnd.nextDouble() < 0.35,
        ),
    ];
  }

  /// A fixed schedule of meteors, 6–10 s apart, looped. Deterministic from
  /// the seed so the painter can be rebuilt freely without losing its place.
  static List<_Meteor> _scheduleMeteors(int seed) {
    final rnd = math.Random(seed * 31 + 5);
    final out = <_Meteor>[];
    var t = 2.5 + rnd.nextDouble() * 3;
    for (var i = 0; i < 40; i++) {
      out.add(_Meteor(
        t,
        0.25 + rnd.nextDouble() * 0.7,
        rnd.nextDouble() * 0.35,
        math.pi * (0.62 + rnd.nextDouble() * 0.14), // down-left, slightly varied
        0.22 + rnd.nextDouble() * 0.16,
      ));
      t += 6 + rnd.nextDouble() * 4;
    }
    return out;
  }

  double get _loop => _meteors.last.start + 8;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    _paintTrails(canvas, size, t);
    _paintStars(canvas, size, t);
    _paintMeteor(canvas, size, t);
  }

  void _paintStars(Canvas canvas, Size size, double t) {
    final paint = Paint();
    final glow = Paint();
    for (final s in _stars) {
      final tw = 0.62 + 0.38 * math.sin(t * s.speed + s.phase);
      final a = (s.base * tw).clamp(0.0, 1.0);
      final c = s.warm ? AstroColors.star : Colors.white;
      final p = Offset(s.x * size.width, s.y * size.height);
      if (s.r > 1.2) {
        glow.color = c.withValues(alpha: a * 0.22);
        canvas.drawCircle(p, s.r * 3.2, glow);
      }
      paint.color = c.withValues(alpha: a);
      canvas.drawCircle(p, s.r, paint);
    }
  }

  void _paintTrails(Canvas canvas, Size size, double t) {
    if (trails <= 0) return;
    final k = Curves.easeInOutCubic.transform(converge);
    // Celestial pole just past the top-right corner; the point everything
    // converges on sits inside the panel.
    final pole = Offset(size.width * 1.12, -size.height * 0.28);
    final target = Offset(size.width * 0.74, size.height * 0.50);
    final tv = target - pole;
    final tr = tv.distance;
    final ta = math.atan2(tv.dy, tv.dx);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < trails; i++) {
      final f = (i + 1) / (trails + 1);
      final r0 = size.width * (0.55 + f * 0.75);
      final mid0 = ta + (f - 0.5) * 0.10;
      final sweep0 = 0.34 + f * 0.10;
      final r = ui.lerpDouble(r0, tr, k)!;
      final mid = ui.lerpDouble(mid0, ta, k)!;
      final sweep = sweep0 * (1 - k);
      if (sweep < 0.004) continue;
      stroke
        ..strokeWidth = 1.0 + f * 0.6
        ..color = AstroColors.silver.withValues(alpha: 0.10 + f * 0.10 + k * 0.12);
      canvas.drawArc(Rect.fromCircle(center: pole, radius: r), mid - sweep / 2, sweep, false, stroke);
    }
    if (k > 0.02) {
      // The point they collapse into: the alignment mark.
      final pulse = 0.85 + 0.15 * math.sin(t * 2.2);
      final a = k * k;
      canvas.drawCircle(
          target, 9 * pulse, Paint()..color = AstroColors.aligned.withValues(alpha: 0.16 * a));
      canvas.drawCircle(
          target, 4.2 * pulse, Paint()..color = AstroColors.aligned.withValues(alpha: 0.55 * a));
      canvas.drawCircle(target, 1.8, Paint()..color = Colors.white.withValues(alpha: a));
    }
  }

  void _paintMeteor(Canvas canvas, Size size, double t) {
    if (t <= 0) return;
    final lt = t % _loop;
    for (final m in _meteors) {
      final p = (lt - m.start) / _meteorSeconds;
      if (p < 0 || p > 1) continue;
      final len = m.length * size.width;
      final dir = Offset(math.cos(m.angle), math.sin(m.angle));
      final origin = Offset(m.x * size.width, m.y * size.height);
      final travel = len * 1.6;
      final head = origin + dir * (Curves.easeOut.transform(p) * travel);
      final tailLen = len * math.sin(p * math.pi); // grows, then burns out
      final tail = head - dir * tailLen;
      final fade = (1 - p).clamp(0.0, 1.0);
      final paint = Paint()
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          tail,
          head,
          [AstroColors.star.withValues(alpha: 0), AstroColors.star.withValues(alpha: 0.95 * fade)],
        );
      canvas.drawLine(tail, head, paint);
      canvas.drawCircle(head, 1.8, Paint()..color = Colors.white.withValues(alpha: fade));
      return; // never two at once
    }
  }

  @override
  bool shouldRepaint(StarFieldPainter old) =>
      old.converge != converge ||
      old.seed != seed ||
      old.density != density ||
      old.trails != trails ||
      old.time != time;
}
