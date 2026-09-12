import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app's graphic signature: a horizontal loudness envelope, mirrored
/// above and below a centre line like an audio waveform, that slowly
/// "breathes". Two painters share the shape maths:
///
/// - [BreathingWavePainter] — the home hero. A fixed, seeded envelope (the
///   same silhouette every launch, so it reads as a logo) whose amplitude
///   swells and settles on a 4-second cycle and whose ripples drift.
/// - [LiveWavePainter] — the recording screen. The envelope is a rolling
///   history of real loudness samples, newest on the right, so the user
///   watches the night being drawn.
///
/// Both are pure functions of their inputs and repaint only when driven.

class BreathingWavePainter extends CustomPainter {
  BreathingWavePainter({
    required this.breath,
    required this.drift,
    required this.color,
    required this.glowColor,
    this.seed = 7,
    this.centerY = 0.42,
    this.maxAmplitude = 0.30,
  });

  /// 0..1 position in the breathing cycle (0 = exhale, 0.5 = full inhale).
  final double breath;

  /// Slow phase drift in radians — the ripples crawl sideways.
  final double drift;

  final Color color;
  final Color glowColor;
  final int seed;

  /// Vertical centre of the wave as a fraction of the height.
  final double centerY;

  /// Half-height of the loudest peak as a fraction of the height.
  final double maxAmplitude;

  @override
  void paint(Canvas canvas, Size size) {
    final double cy = size.height * centerY;
    // Inhale/exhale: amplitude between 62% and 100% on an eased sine.
    final double swell = 0.62 + 0.38 * (0.5 - 0.5 * math.cos(breath * math.pi * 2));
    final double amp = size.height * maxAmplitude * swell;

    // Soft glow pooled under the wave.
    final Rect glowRect = Rect.fromLTWH(0, cy - amp * 0.6, size.width, size.height - cy + amp);
    canvas.drawRect(
      glowRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 0.9,
          colors: [glowColor.withValues(alpha: 0.55), glowColor.withValues(alpha: 0)],
        ).createShader(glowRect),
    );

    final int n = (size.width / 3).ceil().clamp(40, 400);
    final List<double> ys = List<double>.filled(n + 1, 0);
    final math.Random rng = math.Random(seed);
    // Frequencies/phases come from the seeded RNG in a fixed order, so the
    // silhouette is identical every frame and every launch (it is a logo).
    final List<double> fs = List.generate(4, (_) => 1.5 + rng.nextDouble() * 4.5);
    final List<double> ps = List.generate(4, (_) => rng.nextDouble() * math.pi * 2);
    for (int i = 0; i <= n; i++) {
      final double x = i / n;
      double v = 0, w = 0;
      for (int k = 0; k < 4; k++) {
        final double a = 1 / (k + 1);
        v += a * math.sin(x * fs[k] * math.pi * 2 + ps[k] + drift * (k.isEven ? 1 : -1));
        w += a;
      }
      // Taper toward both edges so the wave fades in from nothing.
      final double taper = math.sin(x * math.pi);
      final double e = (v / w).abs() * (0.35 + 0.65 * taper) + 0.06 * taper;
      ys[i] = e.clamp(0.0, 1.0) * amp;
    }

    final Path fill = Path()..moveTo(0, cy);
    for (int i = 0; i <= n; i++) {
      fill.lineTo(size.width * i / n, cy - ys[i]);
    }
    for (int i = n; i >= 0; i--) {
      fill.lineTo(size.width * i / n, cy + ys[i]);
    }
    fill.close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.55),
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.55),
          ],
        ).createShader(Rect.fromLTWH(0, cy - amp, size.width, amp * 2)),
    );

    // Crisp top edge — the "line" the eye follows.
    final Path top = Path()..moveTo(0, cy - ys[0]);
    for (int i = 1; i <= n; i++) {
      top.lineTo(size.width * i / n, cy - ys[i]);
    }
    canvas.drawPath(
      top,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant BreathingWavePainter old) =>
      old.breath != breath ||
      old.drift != drift ||
      old.color != color ||
      old.glowColor != glowColor ||
      old.seed != seed;
}

/// Recording screen: a rolling strip of loudness samples (0..1, newest last)
/// drawn as a mirrored bar waveform. [pulse] (0..1) adds the same slow breath
/// so a silent room still looks alive.
class LiveWavePainter extends CustomPainter {
  LiveWavePainter({
    required this.samples,
    required this.pulse,
    required this.color,
    required this.accent,
    required this.trackColor,
  });

  final List<double> samples;
  final double pulse;
  final Color color;
  final Color accent;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double cy = size.height / 2;
    canvas.drawRect(
      Rect.fromLTWH(0, cy - 0.75, size.width, 1.5),
      Paint()..color = trackColor,
    );
    if (samples.isEmpty) return;
    final int n = samples.length;
    final double slot = size.width / n;
    final double barW = math.max(2.0, slot * 0.55);
    final double breathe = 0.85 + 0.15 * (0.5 - 0.5 * math.cos(pulse * math.pi * 2));
    final Paint p = Paint()..strokeCap = StrokeCap.round;
    for (int i = 0; i < n; i++) {
      final double v = samples[i].clamp(0.0, 1.0);
      // Minimum 4px so silence is a dotted centre line, not nothing.
      final double h = math.max(4.0, v * size.height * 0.92 * breathe);
      final double x = i * slot + slot / 2;
      final double age = i / n; // 0 = oldest, 1 = newest
      // Newest bars are brightest; the loud ones tip into the accent.
      final Color c = Color.lerp(
        color.withValues(alpha: 0.25 + 0.6 * age),
        accent,
        (v - 0.6).clamp(0.0, 0.4) * 2.5 * age,
      )!;
      p
        ..color = c
        ..strokeWidth = barW;
      canvas.drawLine(Offset(x, cy - h / 2), Offset(x, cy + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant LiveWavePainter old) => true;
}

/// Two concentric rings that expand from a circle and fade — the mic
/// button's "listening" halo. [t] is the 0..1 cycle position; the second ring
/// runs half a cycle behind the first.
class RipplePainter extends CustomPainter {
  RipplePainter({
    required this.t,
    required this.color,
    required this.innerRadius,
    required this.reach,
  });

  final double t;
  final Color color;
  final double innerRadius;

  /// How far beyond [innerRadius] a ring travels before it vanishes.
  final double reach;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    for (final double phase in const [0.0, 0.5]) {
      final double k = (t + phase) % 1.0;
      final double eased = Curves.easeOut.transform(k);
      final double r = innerRadius + reach * eased;
      final double alpha = (1 - k) * 0.55;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 - k
          ..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant RipplePainter old) =>
      old.t != t || old.color != color || old.innerRadius != innerRadius || old.reach != reach;
}
