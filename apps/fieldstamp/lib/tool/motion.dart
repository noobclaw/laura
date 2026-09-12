import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// SiteStamp's motion + graphic language: the safety-orange accent used for
/// the shutter ring and accuracy circle, durations that collapse to zero when
/// the OS asks for reduced motion, and the two self-drawn painters (aperture
/// blades, accuracy ring) that give the viewfinder its signature.
abstract final class Motion {
  /// Safety orange — one accent on a forest-green product, reserved for the
  /// shutter ring, the accuracy circle and the "GPS is poor" state.
  static const Color safetyOrange = Color(0xFFFF8F00);

  /// Fix-quality green used on-screen (brighter than the seed so it reads on
  /// the black viewfinder).
  static const Color fixGreen = Color(0xFF69F0AE);

  static const Curve standard = Curves.easeInOutCubic;
  static const Curve enter = Curves.easeOutCubic;

  /// A duration that respects `MediaQuery.disableAnimations`.
  static Duration of(BuildContext context, int ms) =>
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Duration(milliseconds: ms);

  /// GPS accuracy bucket: 0 = no fix, 1 = poor (> 15 m), 2 = good.
  static int accuracyBucket(double? accuracy, {required bool hasFix}) {
    if (!hasFix) return 0;
    if (accuracy == null || accuracy > 15) return 1;
    return 2;
  }

  static Color accuracyColor(int bucket) => switch (bucket) {
        2 => fixGreen,
        1 => safetyOrange,
        _ => Colors.white54,
      };
}

/// Six iris blades. `closure` runs 0 (open, a thin ring of blades around a
/// wide pupil) to 1 (shut to a pinhole). Each blade is the region between the
/// outer circle and two chords; the chord through anchor `i` makes angle
/// `phi` with the radius, so the pupil's apothem is R·sin(phi).
class AperturePainter extends CustomPainter {
  const AperturePainter({
    required this.closure,
    required this.blade,
    required this.seam,
    this.rotation = 0,
  });

  final double closure;
  final Color blade;
  final Color seam;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final phi = lerpDouble(52, 5, closure.clamp(0, 1))! * math.pi / 180;
    final anchors = <Offset>[];
    final dirs = <Offset>[];
    for (var i = 0; i < 6; i++) {
      final th = i * math.pi / 3 - math.pi / 2 + rotation;
      anchors.add(c + Offset(math.cos(th), math.sin(th)) * r);
      final d = th + math.pi - phi;
      dirs.add(Offset(math.cos(d), math.sin(d)));
    }
    double cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
    final fill = Paint()..color = blade;
    final line = Paint()
      ..color = seam
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r * 0.05)
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    for (var i = 0; i < 6; i++) {
      final j = (i + 1) % 6;
      final a = anchors[i];
      final b = anchors[j];
      final denom = cross(dirs[i], dirs[j]);
      if (denom.abs() < 1e-6) continue;
      final t = cross(b - a, dirs[j]) / denom;
      final ix = a + dirs[i] * t;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..arcToPoint(b, radius: Radius.circular(r), clockwise: true)
        ..lineTo(ix.dx, ix.dy)
        ..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(AperturePainter old) =>
      old.closure != closure ||
      old.blade != blade ||
      old.seam != seam ||
      old.rotation != rotation;
}

/// A tiny "accuracy circle": an orange ring whose filled core grows with the
/// GPS error radius — the same idea as the translucent circle on a map, shrunk
/// to a 20 px glyph beside the coordinates.
class AccuracyRingPainter extends CustomPainter {
  const AccuracyRingPainter({required this.fill, required this.color});

  /// 0 = pin-sharp, 1 = the whole ring is uncertainty.
  final double fill;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      c,
      lerpDouble(r * 0.18, r - 2, fill.clamp(0, 1))!,
      Paint()..color = color.withValues(alpha: 0.45),
    );
    canvas.drawCircle(c, 1.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(AccuracyRingPainter old) =>
      old.fill != fill || old.color != color;
}

/// One L-shaped viewfinder corner. Colour transitions with GPS quality.
class CornerBracket extends StatelessWidget {
  const CornerBracket({
    super.key,
    required this.color,
    required this.alignment,
    this.size = 26,
    this.thickness = 3,
  });

  final Color color;
  final Alignment alignment;
  final double size;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final top = alignment.y < 0;
    final left = alignment.x < 0;
    final side = BorderSide(color: color, width: thickness);
    return AnimatedContainer(
      duration: Motion.of(context, 300),
      curve: Motion.standard,
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border(
          top: top ? side : BorderSide.none,
          bottom: top ? BorderSide.none : side,
          left: left ? side : BorderSide.none,
          right: left ? BorderSide.none : side,
        ),
        borderRadius: BorderRadius.only(
          topLeft: top && left ? const Radius.circular(6) : Radius.zero,
          topRight: top && !left ? const Radius.circular(6) : Radius.zero,
          bottomLeft: !top && left ? const Radius.circular(6) : Radius.zero,
          bottomRight: !top && !left ? const Radius.circular(6) : Radius.zero,
        ),
      ),
    );
  }
}

/// Vertical "odometer" switch for a changing value: the old text slides up
/// and fades while the new one slides in from below.
class RollingText extends StatelessWidget {
  const RollingText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: Motion.of(context, 220),
        switchInCurve: Motion.enter,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.6),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: Text(text, key: ValueKey(text), style: style, maxLines: 1),
      ),
    );
  }
}
