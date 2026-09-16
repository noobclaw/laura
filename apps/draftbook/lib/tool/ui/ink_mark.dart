import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draftbook's signature scene (PIPELINE 视觉标准 10): a nib writing a line of
/// ink across ruled paper.
///
/// The stroke is a parametric curve sampled into short segments, each drawn
/// with its own width, which is how a calligraphic swell is faked without a
/// variable-width stroke API. The nib rides the head of the stroke with a soft
/// bleed of ink under it; behind it the line settles to its final opacity.
///
/// [progress] (0..1) is the fraction of the stroke that has been written — the
/// home hero drives it from the day's word count, so the mark *is* the
/// progress bar rather than decoration sitting next to one.
class InkStroke extends StatelessWidget {
  const InkStroke({
    super.key,
    required this.progress,
    this.ink,
    this.paper,
    this.showNib = true,
    this.ruled = true,
    this.thickness = 1,
  });

  final double progress;
  final Color? ink;
  final Color? paper;
  final bool showNib;
  final bool ruled;

  /// Multiplier on the stroke width, for the big empty-state mark.
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _InkStrokePainter(
        progress: progress.clamp(0.0, 1.0),
        ink: ink ?? cs.primary,
        paper: paper ?? cs.onSurfaceVariant.withValues(alpha: 0.22),
        showNib: showNib,
        ruled: ruled,
        thickness: thickness,
      ),
    );
  }
}

class _InkStrokePainter extends CustomPainter {
  _InkStrokePainter({
    required this.progress,
    required this.ink,
    required this.paper,
    required this.showNib,
    required this.ruled,
    required this.thickness,
  });

  final double progress;
  final Color ink;
  final Color paper;
  final bool showNib;
  final bool ruled;
  final double thickness;

  static const int _samples = 132;

  /// The written line, in unit space (x 0..1, y around 0.5).
  Offset _point(double t, Size size) {
    // Two sines of different periods read as handwriting rather than as a sine
    // wave; the slow drift keeps the baseline from looking mechanical.
    final y = 0.5 +
        0.155 * math.sin(t * math.pi * 3.1 + 0.4) +
        0.055 * math.sin(t * math.pi * 7.7 + 1.1) -
        0.06 * t;
    return Offset(t * size.width, y * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (ruled) {
      final rule = Paint()
        ..color = paper
        ..strokeWidth = 1;
      for (var i = 1; i <= 3; i++) {
        final y = size.height * i / 4;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
      }
    }

    final maxWidth = (size.height * 0.055 + 1.6) * thickness;
    final head = progress;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < _samples; i++) {
      final t0 = i / _samples;
      final t1 = (i + 1) / _samples;
      if (t0 > head) break;
      final a = _point(t0, size);
      final b = _point(math.min(t1, head), size);
      // Swell in the middle of each hand-drawn arc, thin at the ends.
      final swell = 0.45 + 0.55 * math.sin(t0 * math.pi * 3.1 + 0.4).abs();
      // The last centimetre of the stroke is still wet: brighter and wider.
      final wetness = (1 - ((head - t0) / 0.06)).clamp(0.0, 1.0);
      paint
        ..color = Color.lerp(ink.withValues(alpha: 0.86), ink, wetness)!
        ..strokeWidth = maxWidth * (0.5 + 0.5 * swell) * (1 + 0.35 * wetness);
      canvas.drawLine(a, b, paint);
    }

    if (showNib && progress > 0.001 && progress < 0.999) {
      final p = _point(head, size);
      final ahead = _point(math.min(head + 0.01, 1), size);
      final angle = math.atan2(ahead.dy - p.dy, ahead.dx - p.dx);
      // Ink bleeding under the nib.
      canvas.drawCircle(
        p,
        maxWidth * 1.5,
        Paint()..color = ink.withValues(alpha: 0.18),
      );
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(angle);
      final nibLength = maxWidth * 5.2;
      final nibWidth = maxWidth * 2.0;
      final nib = Path()
        ..moveTo(nibLength * 0.28, 0)
        ..lineTo(-nibLength * 0.72, -nibWidth)
        ..lineTo(-nibLength * 0.55, 0)
        ..lineTo(-nibLength * 0.72, nibWidth)
        ..close();
      canvas.drawPath(nib, Paint()..color = ink);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_InkStrokePainter old) =>
      old.progress != progress ||
      old.ink != ink ||
      old.paper != paper ||
      old.showNib != showNib ||
      old.thickness != thickness;
}

/// The stroke, writing itself once when it appears and then holding at
/// [target]. Honours "reduce motion": it simply appears at [target] instead.
class AnimatedInkStroke extends StatefulWidget {
  const AnimatedInkStroke({
    super.key,
    required this.target,
    this.duration = const Duration(milliseconds: 1500),
    this.ink,
    this.thickness = 1,
    this.ruled = true,
  });

  final double target;
  final Duration duration;
  final Color? ink;
  final double thickness;
  final bool ruled;

  @override
  State<AnimatedInkStroke> createState() => _AnimatedInkStrokeState();
}

class _AnimatedInkStrokeState extends State<AnimatedInkStroke>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedInkStroke old) {
    super.didUpdateWidget(old);
    // A new target (more words written today) re-draws the tail only.
    if (old.target != widget.target && _c.isCompleted) {
      _c
        ..value = 0.82
        ..forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => InkStroke(
        progress: widget.target * Curves.easeInOutCubic.transform(_c.value),
        ink: widget.ink,
        thickness: widget.thickness,
        ruled: widget.ruled,
        showNib: _c.value < 1,
      ),
    );
  }
}

/// The app mark: a nib over a page, used in the empty state and the About
/// dialog. Self-drawn so it scales to any size without an asset.
class DraftbookMark extends StatelessWidget {
  const DraftbookMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(
          ink: cs.primary,
          page: cs.surfaceContainerLowest,
          edge: cs.outlineVariant,
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.ink, required this.page, required this.edge});

  final Color ink;
  final Color page;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.16, s * 0.08, s * 0.62, s * 0.84),
      Radius.circular(s * 0.08),
    );
    canvas
      ..drawRRect(r, Paint()..color = page)
      ..drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.022
          ..color = edge,
      );

    final line = Paint()
      ..color = ink.withValues(alpha: 0.28)
      ..strokeWidth = s * 0.035
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = s * (0.26 + i * 0.14);
      final right = i == 3 ? 0.46 : 0.66;
      canvas.drawLine(Offset(s * 0.26, y), Offset(s * right, y), line);
    }

    // The nib, laid across the page from the lower right.
    canvas.save();
    canvas.translate(s * 0.66, s * 0.62);
    canvas.rotate(-math.pi / 4);
    final nib = Path()
      ..moveTo(s * 0.30, 0)
      ..lineTo(-s * 0.12, -s * 0.085)
      ..lineTo(-s * 0.02, 0)
      ..lineTo(-s * 0.12, s * 0.085)
      ..close();
    canvas
      ..drawPath(nib, Paint()..color = ink)
      ..drawCircle(Offset(s * 0.34, 0), s * 0.035,
          Paint()..color = ink.withValues(alpha: 0.5));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.ink != ink || old.page != page || old.edge != edge;
}
