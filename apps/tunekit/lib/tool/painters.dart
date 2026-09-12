import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'music/theory.dart';

/// Shared geometry of the tuner dial: a 150° arc from −50 to +50 cents,
/// pivot near the bottom edge of the box.
class _DialGeometry {
  _DialGeometry(Size size)
      : r = math.min(size.width / 2, size.height / 1.15) - 8,
        center = Offset(size.width / 2, size.height * 0.92);

  static const double sweepDeg = 150;
  final double r;
  final Offset center;
  double get startAngle => math.pi * (270 - sweepDeg / 2) / 180;
  double get sweep => math.pi * sweepDeg / 180;
  Rect get rect => Rect.fromCircle(center: center, radius: r);

  /// Unit vector toward the dial position for [cents] (clamped ±50).
  Offset dir(double cents) {
    final a = startAngle + sweep * ((cents.clamp(-50.0, 50.0) + 50) / 100);
    return Offset(math.cos(a), math.sin(a));
  }
}

/// The static part of the tuner's hero: the walnut face, its growth rings,
/// the track, the green ±5 band and the tick marks. Only depends on the
/// colour scheme and whether a pitch is present, so wrap it in a
/// [RepaintBoundary] and it is rasterised once and reused for every needle
/// frame ([TunerNeedlePainter] draws on top as a foreground painter).
class TunerDialFacePainter extends CustomPainter {
  const TunerDialFacePainter({required this.active, required this.scheme});

  final bool active;
  final ColorScheme scheme;

  static const double sweepDeg = _DialGeometry.sweepDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _DialGeometry(size);
    final r = g.r;
    final center = g.center;
    final startAngle = g.startAngle;
    final sweep = g.sweep;
    final rect = g.rect;

    // Wood face: a radial gradient lit off-centre, then fine concentric
    // rings like the growth lines of a turned walnut disc. Clipped to the
    // dial's wedge so it reads as a face, not a background.
    final face = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(Rect.fromCircle(center: center, radius: r + 4), startAngle - 0.06, sweep + 0.12, false)
      ..close();
    canvas.save();
    canvas.clipPath(face);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, 0.35),
          radius: 1.1,
          colors: const [Color(0xFF6B4B3E), Color(0xFF4A3129), Color(0xFF2A1C17)],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: r + 4)),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var rr = r * 0.22; rr < r - 22; rr += 7) {
      final phase = (rr / 7).floor();
      ring.color = Colors.white.withValues(alpha: phase % 3 == 0 ? 0.06 : 0.03);
      canvas.drawArc(Rect.fromCircle(center: center, radius: rr), startAngle, sweep, false, ring);
    }
    canvas.restore();

    // Track.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.28);
    canvas.drawArc(rect, startAngle, sweep, false, track);
    final trackHi = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r + 7.5), startAngle, sweep, false, trackHi);

    // In-tune band (±5 cents).
    final bandSweep = sweep * (10 / 100);
    final band = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.butt
      ..color = kInTuneGreen.withValues(alpha: active ? 0.9 : 0.35);
    canvas.drawArc(rect, startAngle + sweep / 2 - bandSweep / 2, bandSweep, false, band);

    // Ticks every 10 cents, minor every 5.
    for (var c = -50; c <= 50; c += 5) {
      final major = c % 10 == 0;
      final a = startAngle + sweep * ((c + 50) / 100);
      final inner = r - (major ? 26 : 20);
      final outer = r - 12;
      final p = Paint()
        ..color = scheme.onSurface.withValues(alpha: major ? 0.6 : 0.3)
        ..strokeWidth = major ? 2 : 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * inner,
        center + Offset(math.cos(a), math.sin(a)) * outer,
        p,
      );
      if (c == -50 || c == 0 || c == 50) {
        final tp = TextPainter(
          text: TextSpan(
            text: c == 0 ? '0' : (c > 0 ? '+$c' : '$c'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final pos = center + Offset(math.cos(a), math.sin(a)) * (r - 42);
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(TunerDialFacePainter old) => old.active != active || old.scheme != scheme;
}

/// The moving part of the tuner's hero, painted over [TunerDialFacePainter]:
/// the amber needle with its brass pivot and the rim halo. [cents] is the
/// needle's *displayed* position (the page springs it toward the reading);
/// null = no signal (needle rests at centre, dimmed). [glow] 0..1 lights an
/// amber halo around the rim while in tune; the page pulses it. This is the
/// only thing repainted per animation frame, so it uses no mask filters —
/// both glows are stacked translucent wide strokes instead of a blur.
class TunerNeedlePainter extends CustomPainter {
  const TunerNeedlePainter({
    required this.cents,
    required this.active,
    required this.inTune,
    required this.scheme,
    this.glow = 0,
  });

  final double? cents;
  final bool active;
  final bool inTune;
  final ColorScheme scheme;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _DialGeometry(size);
    final r = g.r;
    final center = g.center;
    final startAngle = g.startAngle;
    final sweep = g.sweep;

    // Amber halo on the rim when in tune (pulsed by the page): three
    // concentric translucent strokes, soft enough to read as a glow.
    if (glow > 0.01) {
      final haloRect = Rect.fromCircle(center: center, radius: r + 10);
      for (final (w, a) in [(22.0 + 8 * glow, 0.06), (14.0 + 6 * glow, 0.10), (8.0 + 4 * glow, 0.16)]) {
        canvas.drawArc(
          haloRect,
          startAngle,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round
            ..color = kBeatAmber.withValues(alpha: a * (0.5 + 0.5 * glow)),
        );
      }
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kBeatAmber.withValues(alpha: 0.35 + 0.45 * glow);
      canvas.drawArc(Rect.fromCircle(center: center, radius: r + 9), startAngle, sweep, false, rim);
    }

    // Needle: amber by default, green once it sits in the band.
    final dir = g.dir(cents ?? 0);
    final tip = center + dir * (r - 6);
    final tail = center - dir * 14;
    final needleColor = !active
        ? scheme.onSurface.withValues(alpha: 0.25)
        : (inTune ? kInTuneGreen : kBeatAmber);
    if (active) {
      // Glow: two translucent wide strokes under the body (no MaskFilter).
      for (final (w, a) in const [(12.0, 0.12), (7.0, 0.22)]) {
        canvas.drawLine(
          center,
          tip,
          Paint()
            ..color = needleColor.withValues(alpha: a)
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    // Tapered body: a thin polygon rather than a stroke so the tip is sharp.
    final side = Offset(-dir.dy, dir.dx);
    final body = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(center.dx + side.dx * 3.2, center.dy + side.dy * 3.2)
      ..lineTo(tail.dx + side.dx * 2.2, tail.dy + side.dy * 2.2)
      ..lineTo(tail.dx - side.dx * 2.2, tail.dy - side.dy * 2.2)
      ..lineTo(center.dx - side.dx * 3.2, center.dy - side.dy * 3.2)
      ..close();
    canvas.drawPath(body, Paint()..color = needleColor);
    // Brass pivot.
    canvas.drawCircle(center, 11, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.4),
          colors: [Color(0xFFFFE0A8), Color(0xFFC98B2E), Color(0xFF7A4E10)],
          stops: [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: center, radius: 9)),
    );
    canvas.drawCircle(center, 3, Paint()..color = needleColor);
  }

  @override
  bool shouldRepaint(TunerNeedlePainter old) =>
      old.cents != cents ||
      old.active != active ||
      old.inTune != inTune ||
      old.scheme != scheme ||
      old.glow != glow;
}

/// Guitar/ukulele/bass fretboard. Two modes:
///  - dictionary: every position whose pitch class is in [highlight] gets a
///    dot (root filled amber, others primary);
///  - voicing: [voicing] gives one fret per string (−1 muted): open strings
///    show "O", muted "×", fretted a dot.
/// Strings run bottom (lowest) to top; frets left to right from the nut.
class FretboardPainter extends CustomPainter {
  const FretboardPainter({
    required this.strings,
    required this.scheme,
    this.frets = 12,
    this.highlight = const {},
    this.root,
    this.voicing,
    this.flats = false,
    this.stringStatus,
  });

  final List<int> strings;
  final ColorScheme scheme;
  final int frets;
  final Set<int> highlight;
  final int? root;
  final List<int>? voicing;
  final bool flats;

  /// Per-string check result: null = pending, true = ok, false = off.
  final List<bool?>? stringStatus;

  @override
  void paint(Canvas canvas, Size size) {
    final n = strings.length;
    if (n == 0) return;
    const left = 30.0;
    const right = 10.0;
    const top = 14.0;
    const bottom = 22.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    final fretW = w / (frets + 0.5);
    final gap = h / (n - 1);

    final board = Paint()..color = scheme.surfaceContainerLowest.withValues(alpha: 0.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, top - 6, w, h + 12), const Radius.circular(8)),
      board,
    );
    // Nut.
    canvas.drawRect(
      Rect.fromLTWH(left - 4, top - 6, 5, h + 12),
      Paint()..color = scheme.onSurface.withValues(alpha: 0.7),
    );
    // Frets.
    final fretPaint = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.28)
      ..strokeWidth = 1.5;
    for (var f = 1; f <= frets; f++) {
      final x = left + f * fretW;
      canvas.drawLine(Offset(x, top - 6), Offset(x, top + h + 6), fretPaint);
    }
    // Inlay markers.
    final inlay = Paint()..color = scheme.onSurface.withValues(alpha: 0.12);
    for (final f in const [3, 5, 7, 9, 12, 15]) {
      if (f > frets) break;
      final x = left + (f - 0.5) * fretW;
      if (f == 12) {
        canvas.drawCircle(Offset(x, top + h * 0.3), 4, inlay);
        canvas.drawCircle(Offset(x, top + h * 0.7), 4, inlay);
      } else {
        canvas.drawCircle(Offset(x, top + h / 2), 4, inlay);
      }
    }
    // Strings (thicker for lower).
    for (var s = 0; s < n; s++) {
      final y = top + h - s * gap;
      canvas.drawLine(
        Offset(left, y),
        Offset(left + w, y),
        Paint()
          ..color = scheme.onSurface.withValues(alpha: 0.5)
          ..strokeWidth = 2.6 - s * (1.6 / math.max(1, n - 1)),
      );
      // Open string label.
      _label(canvas, pitchClassName(pitchClassOf(strings[s]), flats: flats),
          Offset(left - 18, y), scheme.onSurfaceVariant, 11);
    }

    final dotR = math.min(gap * 0.36, fretW * 0.36).clamp(6.0, 13.0);
    if (voicing != null) {
      for (var s = 0; s < n; s++) {
        final f = voicing![s];
        final y = top + h - s * gap;
        final status = stringStatus == null ? null : stringStatus![s];
        final color = status == null
            ? scheme.primary
            : (status ? kInTuneGreen : kOffCoral);
        if (f < 0) {
          _label(canvas, '×', Offset(left - 4 + fretW * 0.25 - 12, y), kOffCoral, 14);
        } else if (f == 0) {
          canvas.drawCircle(
            Offset(left + fretW * 0.25, y),
            dotR * 0.8,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2
              ..color = color,
          );
        } else {
          final x = left + (f - 0.5) * fretW;
          canvas.drawCircle(Offset(x, y), dotR, Paint()..color = color);
          _label(canvas, f.toString(), Offset(x, y), scheme.onPrimary, 11, bold: true);
        }
      }
      return;
    }

    for (var s = 0; s < n; s++) {
      final y = top + h - s * gap;
      for (var f = 0; f <= frets; f++) {
        final pc = pitchClassOf(strings[s] + f);
        if (!highlight.contains(pc)) continue;
        final isRoot = pc == root;
        final x = f == 0 ? left + fretW * 0.25 : left + (f - 0.5) * fretW;
        canvas.drawCircle(
          Offset(x, y),
          dotR,
          Paint()..color = isRoot ? kBeatAmber : scheme.primary,
        );
        _label(canvas, pitchClassName(pc, flats: flats), Offset(x, y),
            isRoot ? kOnAmber : scheme.onPrimary, dotR > 9 ? 10 : 8,
            bold: true);
      }
    }
  }

  void _label(Canvas canvas, String text, Offset center, Color color, double size,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(FretboardPainter old) =>
      old.strings != strings ||
      old.highlight != highlight ||
      old.root != root ||
      old.voicing != voicing ||
      old.stringStatus != stringStatus ||
      old.scheme != scheme;
}

/// Two octaves of piano keys with the given MIDI notes highlighted.
class PianoPainter extends CustomPainter {
  const PianoPainter({
    required this.highlightMidi,
    required this.scheme,
    this.root,
    this.startMidi = 48,
    this.octaves = 2,
    this.flats = false,
  });

  final Set<int> highlightMidi;
  final ColorScheme scheme;
  final int? root;
  final int startMidi;
  final int octaves;
  final bool flats;

  static const _blackOffsets = {1, 3, 6, 8, 10};

  @override
  void paint(Canvas canvas, Size size) {
    final whiteCount = 7 * octaves;
    final ww = size.width / whiteCount;
    final bw = ww * 0.62;
    final bh = size.height * 0.62;
    final whiteColor = scheme.brightness == Brightness.dark
        ? const Color(0xFFF0E8DF)
        : const Color(0xFFFFFCF7);
    const blackColor = Color(0xFF241C18);

    // White keys.
    var wi = 0;
    for (var i = 0; i < 12 * octaves; i++) {
      final midi = startMidi + i;
      if (_blackOffsets.contains(i % 12)) continue;
      final rect = Rect.fromLTWH(wi * ww, 0, ww, size.height);
      final on = highlightMidi.contains(midi);
      final isRoot = on && root != null && pitchClassOf(midi) == root;
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect.deflate(0.8),
            bottomLeft: const Radius.circular(5), bottomRight: const Radius.circular(5)),
        Paint()..color = on ? (isRoot ? kBeatAmber : scheme.primary) : whiteColor,
      );
      if (on) {
        _label(canvas, pitchClassName(pitchClassOf(midi), flats: flats),
            Offset(rect.center.dx, size.height - 14),
            isRoot ? kOnAmber : scheme.onPrimary);
      } else if (i % 12 == 0) {
        _label(canvas, 'C${octaveOf(midi)}', Offset(rect.center.dx, size.height - 14),
            const Color(0xFF7A6A60));
      }
      wi++;
    }
    // Black keys.
    wi = 0;
    for (var i = 0; i < 12 * octaves; i++) {
      final midi = startMidi + i;
      if (!_blackOffsets.contains(i % 12)) {
        wi++;
        continue;
      }
      final x = wi * ww - bw / 2;
      final rect = Rect.fromLTWH(x, 0, bw, bh);
      final on = highlightMidi.contains(midi);
      final isRoot = on && root != null && pitchClassOf(midi) == root;
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect,
            bottomLeft: const Radius.circular(4), bottomRight: const Radius.circular(4)),
        Paint()..color = on ? (isRoot ? kBeatAmber : scheme.primary) : blackColor,
      );
      if (on) {
        _label(canvas, pitchClassName(pitchClassOf(midi), flats: flats),
            Offset(rect.center.dx, bh - 12),
            isRoot ? kOnAmber : scheme.onPrimary, size: 9);
      }
    }
  }

  void _label(Canvas canvas, String text, Offset center, Color color, {double size = 10}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(PianoPainter old) =>
      old.highlightMidi != highlightMidi || old.root != root || old.scheme != scheme;
}

/// Stacked bars (one per day) with a baseline and a light max grid line.
/// [progress] 0..1 grows the bars up from the baseline left to right (each
/// bar starts a little after the one before), so the chart "rises" in.
class StackedBarPainter extends CustomPainter {
  const StackedBarPainter({
    required this.bars,
    required this.colors,
    required this.labels,
    required this.scheme,
    this.highlightIndex,
    this.progress = 1,
  });

  /// bars[day][series] in minutes.
  final List<List<double>> bars;
  final List<Color> colors;
  final List<String> labels;
  final ColorScheme scheme;
  final int? highlightIndex;
  final double progress;

  /// Eased growth of bar [i] at the current [progress]: bars are staggered
  /// across the first 45% of the run so the last one still gets a full rise.
  double _grow(int i) {
    const stagger = 0.45;
    final start = bars.length <= 1 ? 0.0 : stagger * i / (bars.length - 1);
    final t = ((progress - start) / (1 - stagger)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    const bottom = 20.0;
    const top = 10.0;
    final h = size.height - bottom - top;
    final maxVal = bars.fold<double>(0, (m, b) => math.max(m, b.fold(0, (a, v) => a + v)));
    final scale = maxVal <= 0 ? 0.0 : h / (maxVal * 1.1);
    final slot = size.width / bars.length;
    final barW = (slot * 0.62).clamp(4.0, 26.0);

    // Baseline.
    canvas.drawLine(
      Offset(0, top + h),
      Offset(size.width, top + h),
      Paint()..color = scheme.outlineVariant.withValues(alpha: 0.6),
    );
    if (maxVal > 0) {
      final y = top + h - maxVal * scale;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = scheme.outlineVariant.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${maxVal.round()} min',
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width, y - tp.height - 1));
    }

    for (var i = 0; i < bars.length; i++) {
      final x = slot * i + (slot - barW) / 2;
      var y = top + h;
      final total = bars[i].fold(0.0, (a, v) => a + v);
      if (total <= 0) {
        // Empty day: a faint stub so the axis still reads as days.
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y - 3, barW, 3), const Radius.circular(2)),
          Paint()..color = scheme.onSurface.withValues(alpha: 0.08),
        );
      }
      final grow = _grow(i);
      for (var s = 0; s < bars[i].length; s++) {
        final v = bars[i][s];
        if (v <= 0) continue;
        final hh = v * scale * grow;
        final rect = Rect.fromLTWH(x, y - hh, barW, hh);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()..color = colors[s % colors.length].withValues(alpha: highlightIndex == null || highlightIndex == i ? 1 : 0.55),
        );
        y -= hh;
      }
      if (i < labels.length && labels[i].isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurfaceVariant,
              fontWeight: highlightIndex == i ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(slot * i + (slot - tp.width) / 2, top + h + 5));
      }
    }
  }

  @override
  bool shouldRepaint(StackedBarPainter old) =>
      old.bars != bars ||
      old.scheme != scheme ||
      old.highlightIndex != highlightIndex ||
      old.progress != progress;
}

/// A line of in-tune ratios (0..1) per day; null days leave a gap.
/// [progress] 0..1 draws the line in from the left.
class AccuracyLinePainter extends CustomPainter {
  const AccuracyLinePainter({
    required this.values,
    required this.scheme,
    required this.labels,
    this.progress = 1,
  });

  final List<double?> values;
  final ColorScheme scheme;
  final List<String> labels;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const bottom = 20.0;
    const top = 10.0;
    final h = size.height - bottom - top;
    final slot = size.width / values.length;
    for (final g in const [0.5, 1.0]) {
      final y = top + h - h * g;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = scheme.outlineVariant.withValues(alpha: g == 1 ? 0.35 : 0.5),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${(g * 100).round()}%',
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width, y - tp.height - 1));
    }
    canvas.drawLine(
      Offset(0, top + h),
      Offset(size.width, top + h),
      Paint()..color = scheme.outlineVariant.withValues(alpha: 0.6),
    );

    // Reveal: everything right of the sweep line is clipped away until the
    // run completes (labels and grid are drawn above, unclipped).
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * Curves.easeOutCubic.transform(progress.clamp(0, 1)), size.height));
    Path? path;
    final line = Paint()
      ..color = kInTuneGreen
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final x = slot * i + slot / 2;
      if (v == null) {
        if (path != null) canvas.drawPath(path, line);
        path = null;
      } else {
        final y = top + h - h * v.clamp(0, 1);
        if (path == null) {
          path = Path()..moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = kInTuneGreen);
      }
    }
    if (path != null) canvas.drawPath(path, line);
    canvas.restore();
    for (var i = 0; i < values.length; i++) {
      if (i < labels.length && labels[i].isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
              text: labels[i],
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(slot * i + (slot - tp.width) / 2, top + h + 5));
      }
    }
  }

  @override
  bool shouldRepaint(AccuracyLinePainter old) =>
      old.values != values || old.scheme != scheme || old.progress != progress;
}
