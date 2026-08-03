import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'models.dart';

/// The sky dome: a polar plot of what you would see lying on your back. Zenith
/// at the centre, horizon at the rim, north up, east right — the same mental
/// model every planetarium uses, so the track on screen maps directly onto the
/// track overhead.
class SkyDomePainter extends CustomPainter {
  SkyDomePainter({
    required this.track,
    required this.scheme,
    required this.nowIndex,
  });

  final List<PassSample> track;
  final ColorScheme scheme;

  /// Index of the sample closest to now, or null when the pass is not running.
  final int? nowIndex;

  static const double _labelInset = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - _labelInset - 8;
    if (radius <= 0) return;

    _paintGrid(canvas, center, radius);
    _paintTrack(canvas, center, radius);
    _paintLabels(canvas, center, radius);
  }

  Offset _project(Offset center, double radius, double azDeg, double elDeg) {
    final r = radius * ((90.0 - elDeg.clamp(0.0, 90.0)) / 90.0);
    final a = azDeg * math.pi / 180.0;
    return Offset(center.dx + r * math.sin(a), center.dy - r * math.cos(a));
  }

  void _paintGrid(Canvas canvas, Offset center, double radius) {
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = scheme.outlineVariant.withValues(alpha: 0.55);
    final horizon = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = scheme.outlineVariant;

    // Elevation rings at 30 and 60 degrees, plus the horizon itself.
    canvas.drawCircle(center, radius, horizon);
    canvas.drawCircle(center, radius * 2 / 3, faint);
    canvas.drawCircle(center, radius / 3, faint);

    // Cardinal spokes.
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final inner = i.isEven ? 0.0 : radius * 2 / 3;
      canvas.drawLine(
        Offset(center.dx + inner * math.sin(a), center.dy - inner * math.cos(a)),
        Offset(
            center.dx + radius * math.sin(a), center.dy - radius * math.cos(a)),
        faint,
      );
    }

    // Zenith tick.
    canvas.drawCircle(
      center,
      2.5,
      Paint()..color = scheme.outlineVariant,
    );
  }

  void _paintTrack(Canvas canvas, Offset center, double radius) {
    if (track.length < 2) return;

    // Segment by segment so a satellite entering the Earth's shadow visibly
    // changes character mid-arc instead of the whole pass reading as one state.
    for (var i = 0; i < track.length - 1; i++) {
      final a = track[i];
      final b = track[i + 1];
      final p1 = _project(center, radius, a.azimuthDeg, a.elevationDeg);
      final p2 = _project(center, radius, b.azimuthDeg, b.elevationDeg);
      final lit = a.sunlit && b.sunlit;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = lit ? 4.0 : 2.4
        ..color = lit
            ? kOrbitCyan
            : kEclipseViolet.withValues(alpha: 0.75);
      if (lit) {
        // A soft glow under the visible part — this is the bit the user is
        // actually going outside for.
        canvas.drawLine(
          p1,
          p2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 10
            ..color = kOrbitCyan.withValues(alpha: 0.16),
        );
      }
      canvas.drawLine(p1, p2, paint);
    }

    final first = track.first;
    final last = track.last;
    var peak = track.first;
    for (final s in track) {
      if (s.elevationDeg > peak.elevationDeg) peak = s;
    }

    _endpoint(canvas, _project(center, radius, first.azimuthDeg, first.elevationDeg));
    _endpoint(canvas, _project(center, radius, last.azimuthDeg, last.elevationDeg));

    // Culmination: the moment worth timing your look for.
    final peakPoint = _project(center, radius, peak.azimuthDeg, peak.elevationDeg);
    canvas.drawCircle(
        peakPoint, 12, Paint()..color = kSignalAmber.withValues(alpha: 0.20));
    canvas.drawCircle(peakPoint, 6, Paint()..color = kSignalAmber);
    canvas.drawCircle(
      peakPoint,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = scheme.surface,
    );

    final idx = nowIndex;
    if (idx != null && idx >= 0 && idx < track.length) {
      final s = track[idx];
      final p = _project(center, radius, s.azimuthDeg, s.elevationDeg);
      canvas.drawCircle(p, 14, Paint()..color = Colors.white.withValues(alpha: 0.18));
      canvas.drawCircle(p, 5, Paint()..color = Colors.white);
    }
  }

  void _endpoint(Canvas canvas, Offset p) {
    canvas.drawCircle(
        p, 4.5, Paint()..color = scheme.surface);
    canvas.drawCircle(
      p,
      4.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kOrbitCyan,
    );
  }

  void _paintLabels(Canvas canvas, Offset center, double radius) {
    // Ring labels: without them the rings are decoration, and the fact that the
    // track starts on the 10-degree ring rather than the rim looks like a bug.
    for (final ring in const [(deg: 30, frac: 2 / 3), (deg: 60, frac: 1 / 3)]) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${ring.deg}°',
          style: TextStyle(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(center.dx + 3, center.dy - radius * ring.frac - tp.height / 2),
      );
    }

    const cardinals = ['N', 'E', 'S', 'W'];
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final pos = Offset(
        center.dx + (radius + _labelInset) * math.sin(a),
        center.dy - (radius + _labelInset) * math.cos(a),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: cardinals[i],
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(SkyDomePainter oldDelegate) =>
      oldDelegate.track != track ||
      oldDelegate.nowIndex != nowIndex ||
      oldDelegate.scheme != scheme;
}

/// The list-card thumbnail: a horizon line with the pass arcing over it. Apex
/// height encodes peak elevation, the ends sit at the true rise/set bearings —
/// so a glance down the list shows which pass climbs highest without reading a
/// single number.
class PassArcPainter extends CustomPainter {
  const PassArcPainter({
    required this.peakElevation,
    required this.startAzimuth,
    required this.endAzimuth,
    required this.visibility,
    required this.scheme,
  });

  final double peakElevation;
  final double startAzimuth, endAzimuth;

  /// The thumbnail is read alongside the badge on the same card; using a
  /// different colour scheme from it would make two elements about the same
  /// fact disagree at a glance.
  final PassVisibility visibility;
  final ColorScheme scheme;

  bool get visible => visibility == PassVisibility.visible;

  @override
  void paint(Canvas canvas, Size size) {
    final baseY = size.height - 6;
    final horizon = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = scheme.outlineVariant;
    canvas.drawLine(Offset(2, baseY), Offset(size.width - 2, baseY), horizon);

    final apex = baseY -
        (size.height - 12) * (peakElevation.clamp(0.0, 90.0) / 90.0).clamp(0.12, 1.0);
    final path = Path()
      ..moveTo(4, baseY)
      ..quadraticBezierTo(size.width / 2, apex * 2 - baseY, size.width - 4, baseY);

    final color = switch (visibility) {
      PassVisibility.visible => kOrbitCyan,
      PassVisibility.eclipsed => kEclipseViolet,
      PassVisibility.daylight => kSignalAmber,
    };
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.16),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    // Apex dot marks culmination.
    canvas.drawCircle(
      Offset(size.width / 2, apex),
      3,
      Paint()..color = visible ? kSignalAmber : color,
    );
  }

  @override
  bool shouldRepaint(PassArcPainter old) =>
      old.peakElevation != peakElevation ||
      old.visibility != visibility ||
      old.scheme != scheme;
}

/// The alignment dial: a compass rose that rotates under a fixed pointer, with
/// the target bearing burned in as a lit wedge. Turning the phone until the
/// wedge sits under the pointer *is* the interaction.
class AlignDialPainter extends CustomPainter {
  const AlignDialPainter({
    required this.headingDeg,
    required this.targetAzimuthDeg,
    required this.onTarget,
    required this.hasHeading,
    required this.scheme,
  });

  final double headingDeg;
  final double targetAzimuthDeg;
  final bool onTarget;

  /// False when the device has no usable magnetometer. The rose still draws —
  /// blanking it would be worse — but muted, because a crisp north-up dial on a
  /// phone that cannot find north is a lie told in pixels.
  final bool hasHeading;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 18;
    if (radius <= 0) return;

    final fade = hasHeading ? 1.0 : 0.35;
    final accent = (onTarget ? kSignalAmber : kOrbitCyan).withValues(alpha: fade);

    // Dial face: a shallow radial fall-off so the rose reads as an instrument
    // rather than a flat hole in the page.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            scheme.surfaceContainerHighest,
            scheme.surfaceContainerLow,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = scheme.outlineVariant,
    );

    // Ticks and cardinal letters rotate with the device heading.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-headingDeg * math.pi / 180.0);

    for (var deg = 0; deg < 360; deg += 15) {
      final major = deg % 45 == 0;
      final a = deg * math.pi / 180.0;
      final outer = radius - 3;
      final inner = radius - (major ? 14.0 : 8.0);
      canvas.drawLine(
        Offset(outer * math.sin(a), -outer * math.cos(a)),
        Offset(inner * math.sin(a), -inner * math.cos(a)),
        Paint()
          ..strokeWidth = major ? 2 : 1
          ..color = scheme.onSurfaceVariant
              .withValues(alpha: (major ? 0.85 : 0.35) * fade),
      );
    }

    // Target wedge.
    final targetAngle = targetAzimuthDeg * math.pi / 180.0;
    final wedge = Path()
      ..moveTo(0, 0)
      ..lineTo((radius - 4) * math.sin(targetAngle - 0.06),
          -(radius - 4) * math.cos(targetAngle - 0.06))
      ..lineTo((radius - 4) * math.sin(targetAngle + 0.06),
          -(radius - 4) * math.cos(targetAngle + 0.06))
      ..close();
    canvas.drawPath(wedge, Paint()..color = accent.withValues(alpha: 0.85));
    canvas.drawCircle(
      Offset((radius - 4) * math.sin(targetAngle),
          -(radius - 4) * math.cos(targetAngle)),
      6,
      Paint()..color = accent,
    );

    const letters = ['N', 'E', 'S', 'W'];
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final r = radius - 28;
      final tp = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: TextStyle(
            color: i == 0
                ? accent
                : scheme.onSurfaceVariant.withValues(alpha: fade),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(r * math.sin(a), -r * math.cos(a)) - Offset(tp.width / 2, tp.height / 2));
    }
    canvas.restore();

    // Fixed pointer at the top — "where the phone is aimed".
    final pointer = Path()
      ..moveTo(center.dx, center.dy - radius - 12)
      ..lineTo(center.dx - 7, center.dy - radius + 2)
      ..lineTo(center.dx + 7, center.dy - radius + 2)
      ..close();
    canvas.drawPath(pointer, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(AlignDialPainter old) =>
      old.headingDeg != headingDeg ||
      old.targetAzimuthDeg != targetAzimuthDeg ||
      old.onTarget != onTarget ||
      old.hasHeading != hasHeading ||
      old.scheme != scheme;
}
