import 'package:flutter/material.dart';

import 'models.dart';

/// Paints the night as a row of loudness bars: the session window is split into
/// fixed buckets and each bar's height is the loudest event in that bucket.
/// Louder bars are brighter, and the single loudest moment is labelled with its
/// dB value so a number lives on the chart, not just in the stats. Empty (quiet)
/// buckets show a faint baseline tick. Pure function of the session.
class NightTimelinePainter extends CustomPainter {
  NightTimelinePainter({
    required this.session,
    required this.barColor,
    required this.trackColor,
    required this.labelColor,
    this.buckets = 48,
    this.progress = 1,
  });

  final SleepSession session;
  final Color barColor;
  final Color trackColor;
  final Color labelColor;
  final int buckets;

  /// 0..1 entrance progress. Bar `i` starts rising at `i * staggerMs` and
  /// takes [barRiseMs]; at 1 every bar is fully up. Pass 1 for a static paint.
  final double progress;

  static const int staggerMs = 20;
  static const int barRiseMs = 360;

  /// Total wall time for the whole staggered entrance (48 bars ≈ 1.3 s).
  static Duration get riseDuration =>
      Duration(milliseconds: staggerMs * 48 + barRiseMs);

  double _rise(int i) {
    if (progress >= 1) return 1;
    final double total = riseDuration.inMilliseconds.toDouble();
    final double t = progress * total - i * staggerMs;
    return Curves.easeOutCubic.transform((t / barRiseMs).clamp(0.0, 1.0));
  }

  static const double _minDb = -60, _maxDb = -10;

  @override
  void paint(Canvas canvas, Size size) {
    final double baseY = size.height;
    canvas.drawRect(
      Rect.fromLTWH(0, baseY - 1.5, size.width, 1.5),
      Paint()..color = trackColor,
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

    final double slot = size.width / buckets;
    final double barW = slot * 0.62;
    int loudestBucket = -1;
    double loudestDb = -1000;

    for (int i = 0; i < buckets; i++) {
      final double? p = peak[i];
      if (p == null) continue;
      final double norm = ((p - _minDb) / (_maxDb - _minDb)).clamp(0.0, 1.0);
      // Reserve ~14px at the top for the loudest-bar dB label.
      final double h = (0.12 + norm * 0.88) * (size.height - 14) * _rise(i);
      final double x = i * slot + (slot - barW) / 2;
      // Louder → brighter.
      final Color c = Color.lerp(barColor, Colors.white, norm * 0.45)!;
      final RRect r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, baseY - h, barW, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(r, Paint()..color = c);
      if (p > loudestDb) {
        loudestDb = p;
        loudestBucket = i;
      }
    }

    // The label lands only once its bar is up.
    if (loudestBucket >= 0 && _rise(loudestBucket) >= 1) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${loudestDb.toStringAsFixed(0)} dB',
          style: TextStyle(
              color: labelColor, fontSize: 10, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      double lx = loudestBucket * slot + slot / 2 - tp.width / 2;
      lx = lx.clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(lx, 0));
    }
  }

  @override
  bool shouldRepaint(covariant NightTimelinePainter old) =>
      old.session != session ||
      old.barColor != barColor ||
      old.trackColor != trackColor ||
      old.labelColor != labelColor ||
      old.progress != progress;
}
