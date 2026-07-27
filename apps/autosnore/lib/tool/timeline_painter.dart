import 'package:flutter/material.dart';

import 'models.dart';

/// Paints the night as a row of loudness bars: the session window is split into
/// fixed buckets and each bar's height is the loudest event in that bucket.
/// Empty (quiet) buckets show a faint baseline tick. Pure function of the
/// session — no state.
class NightTimelinePainter extends CustomPainter {
  NightTimelinePainter({
    required this.session,
    required this.barColor,
    required this.trackColor,
    this.buckets = 48,
  });

  final SleepSession session;
  final Color barColor;
  final Color trackColor;
  final int buckets;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()..color = trackColor;
    // Baseline row.
    final double baseY = size.height;
    canvas.drawRect(
      Rect.fromLTWH(0, baseY - 1.5, size.width, 1.5),
      track,
    );

    final int dur = session.durationMs;
    if (dur <= 0 || session.events.isEmpty) return;

    // Loudest peak per bucket (dBFS, negative — louder = closer to 0).
    final List<double?> peak = List<double?>.filled(buckets, null);
    for (final e in session.events) {
      final double frac = (e.startMs - session.startMs) / dur;
      int b = (frac * buckets).floor();
      if (b < 0) b = 0;
      if (b >= buckets) b = buckets - 1;
      if (peak[b] == null || e.peakDb > peak[b]!) peak[b] = e.peakDb;
    }

    const double minDb = -60, maxDb = -10;
    final double slot = size.width / buckets;
    final double barW = slot * 0.62;
    final Paint bar = Paint()..color = barColor;

    for (int i = 0; i < buckets; i++) {
      final double? p = peak[i];
      if (p == null) continue;
      final double norm = ((p - minDb) / (maxDb - minDb)).clamp(0.12, 1.0);
      final double h = norm * (size.height - 2);
      final double x = i * slot + (slot - barW) / 2;
      final RRect r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, baseY - h, barW, h),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(r, bar);
    }
  }

  @override
  bool shouldRepaint(covariant NightTimelinePainter old) =>
      old.session != session ||
      old.barColor != barColor ||
      old.trackColor != trackColor;
}
