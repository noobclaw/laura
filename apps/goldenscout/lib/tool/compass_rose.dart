import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'astro.dart';

/// A sundial-style compass that plots the Sun's rise/set directions and the
/// current Sun and Moon bearings on a cardinal rose. When [deviceHeading] is
/// supplied the whole rose rotates so "up" is where the phone points, letting
/// the photographer physically aim at the sun's arc.
class CompassRose extends StatelessWidget {
  const CompassRose({
    super.key,
    required this.sunriseAz,
    required this.sunsetAz,
    required this.sun,
    required this.moon,
    this.deviceHeading,
  });

  final double? sunriseAz;
  final double? sunsetAz;
  final SkyPosition? sun;
  final SkyPosition? moon;
  final double? deviceHeading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _RosePainter(
          sunriseAz: sunriseAz,
          sunsetAz: sunsetAz,
          sun: sun,
          moon: moon,
          deviceHeading: deviceHeading,
          ring: scheme.outlineVariant,
          onSurface: scheme.onSurface,
          faint: scheme.onSurfaceVariant,
          sunColor: kGoldenAmber,
          moonColor: scheme.primary,
          horizon: scheme.surfaceContainerHighest,
          skyWarm: kGoldenAmber,
          skyCool: kDuskIndigo,
        ),
      ),
    );
  }
}

class _RosePainter extends CustomPainter {
  _RosePainter({
    required this.sunriseAz,
    required this.sunsetAz,
    required this.sun,
    required this.moon,
    required this.deviceHeading,
    required this.ring,
    required this.onSurface,
    required this.faint,
    required this.sunColor,
    required this.moonColor,
    required this.horizon,
    required this.skyWarm,
    required this.skyCool,
  });

  final double? sunriseAz;
  final double? sunsetAz;
  final SkyPosition? sun;
  final SkyPosition? moon;
  final double? deviceHeading;
  final Color ring, onSurface, faint, sunColor, moonColor, horizon;
  final Color skyWarm, skyCool;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 18;
    final rot = -(deviceHeading ?? 0) * math.pi / 180.0;

    // Convert a compass azimuth (deg from N, clockwise) to a canvas offset at
    // radius [radius]. North is up; the whole rose rotates by [rot].
    Offset at(double azDeg, double radius) {
      final a = (azDeg * math.pi / 180.0) + rot - math.pi / 2;
      return center + Offset(math.cos(a) * radius, math.sin(a) * radius);
    }

    // Horizon disc: a base surface fill (so ticks and labels stay legible in
    // either theme) with a soft dusk-sky radial glow washed over it — warm near
    // the centre where the sun climbs, cooling to blue-hour indigo at the rim.
    canvas.drawCircle(center, r, Paint()..color = horizon.withValues(alpha: 0.35));
    final skyRect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            skyWarm.withValues(alpha: 0.20),
            skyCool.withValues(alpha: 0.16),
          ],
          stops: const [0.0, 1.0],
        ).createShader(skyRect),
    );
    canvas.drawCircle(
        center, r, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ring);

    // Cardinal + intercardinal ticks.
    final tickPaint = Paint()..color = ring..strokeWidth = 1.2;
    for (var a = 0; a < 360; a += 15) {
      final major = a % 90 == 0;
      final inner = at(a.toDouble(), r - (major ? 12 : 6));
      canvas.drawLine(at(a.toDouble(), r), inner, tickPaint);
    }
    for (final c in const [('N', 0.0), ('E', 90.0), ('S', 180.0), ('W', 270.0)]) {
      _label(canvas, at(c.$2, r - 30), c.$1,
          c.$1 == 'N' ? sunColor : onSurface, c.$1 == 'N' ? 16 : 14, true);
    }

    // Sunrise / sunset direction rays.
    if (sunriseAz != null) {
      _ray(canvas, center, at(sunriseAz!, r), sunColor.withValues(alpha: 0.9));
      _dot(canvas, at(sunriseAz!, r), sunColor, 4);
    }
    if (sunsetAz != null) {
      _ray(canvas, center, at(sunsetAz!, r), kDuskRose);
      _dot(canvas, at(sunsetAz!, r), kDuskRose, 4);
    }

    // Current Sun: radius shrinks toward the centre as altitude rises (90° at
    // centre, horizon at the rim); below the horizon it sits on the rim, faded.
    if (sun != null) {
      final below = sun!.altitude < 0;
      final rr = below ? r : r * (1 - (sun!.altitude.clamp(0, 90) / 90));
      final p = at(sun!.azimuth, rr);
      if (!below) {
        // Soft golden halo so the sun reads as light, not a flat pin.
        canvas.drawCircle(
            p,
            18,
            Paint()
              ..color = sunColor.withValues(alpha: 0.55)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
      }
      _dot(canvas, p, sunColor.withValues(alpha: below ? 0.35 : 1), below ? 7 : 10);
      if (!below) {
        canvas.drawCircle(p, 14,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = sunColor.withValues(alpha: 0.5));
      }
    }

    // Current Moon.
    if (moon != null) {
      final below = moon!.altitude < 0;
      final rr = below ? r : r * (1 - (moon!.altitude.clamp(0, 90) / 90));
      final p = at(moon!.azimuth, rr);
      _dot(canvas, p, moonColor.withValues(alpha: below ? 0.3 : 0.95), below ? 5 : 8);
    }

    // Centre pip (zenith).
    canvas.drawCircle(center, 2.5, Paint()..color = faint);
  }

  void _ray(Canvas c, Offset from, Offset to, Color color) {
    c.drawLine(from, to, Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round);
  }

  void _dot(Canvas c, Offset p, Color color, double radius) {
    c.drawCircle(p, radius, Paint()..color = color);
  }

  void _label(Canvas c, Offset p, String text, Color color, double size, bool bold) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_RosePainter old) =>
      old.sun?.azimuth != sun?.azimuth ||
      old.sun?.altitude != sun?.altitude ||
      old.moon?.azimuth != moon?.azimuth ||
      old.moon?.altitude != moon?.altitude ||
      old.deviceHeading != deviceHeading ||
      old.sunriseAz != sunriseAz ||
      old.sunsetAz != sunsetAz;
}
