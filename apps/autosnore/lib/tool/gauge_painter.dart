import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A rounded-cap arc gauge for the 0–100 snore score: a faint full-circle
/// track plus a value arc filled with a sweep gradient from the band colour to
/// a lighter tint. Looks like a designed gauge, not a repurposed spinner.
class ScoreGaugePainter extends CustomPainter {
  ScoreGaugePainter({
    required this.value,
    required this.color,
    required this.trackColor,
  });

  /// 0..100.
  final double value;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double stroke = size.shortestSide * 0.12;
    final Rect rect = Offset.zero & size;
    final Rect arcRect = rect.deflate(stroke / 2 + 1);
    const double start = -math.pi / 2; // 12 o'clock
    final double sweep = (value.clamp(0, 100) / 100) * 2 * math.pi;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, track);

    if (sweep <= 0) return;
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        transform: const GradientRotation(-math.pi / 2),
        colors: [color, Color.lerp(color, Colors.white, 0.4)!],
      ).createShader(arcRect);
    canvas.drawArc(arcRect, start, sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant ScoreGaugePainter old) =>
      old.value != value || old.color != color || old.trackColor != trackColor;
}
