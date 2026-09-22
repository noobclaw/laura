import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../format.dart';
import 'lab_theme.dart';

/// "Nice" step for an axis: 1, 2 or 5 times a power of ten, at least [raw].
double niceStep(double raw) {
  if (raw <= 0 || !raw.isFinite) return 1;
  final exponent = (math.log(raw) / math.ln10).floor();
  final base = math.pow(10, exponent).toDouble();
  for (final m in const [1.0, 2.0, 5.0, 10.0]) {
    if (m * base >= raw * (1 - 1e-9)) return m * base;
  }
  return 10 * base;
}

/// What the scope shows: one trace over the whole run, the playback cursor,
/// and a vertical scale chosen so the trace fills six divisions.
class ScopeTrace {
  ScopeTrace({
    required this.values,
    required this.window,
    required this.unit,
  }) {
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final v in values) {
      if (!v.isFinite) continue;
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    if (!lo.isFinite) {
      lo = 0;
      hi = 0;
    }
    // A flat trace (a DC node) still gets a sensible scale: a fifth of its
    // own magnitude per division, so it sits as a line one division off
    // centre instead of a zero-height smear.
    final span = math.max(hi - lo, math.max(hi.abs(), lo.abs()) * 0.4);
    perDivision = niceStep(span <= 1e-15 ? 1e-3 : span / 5.2);
    final middle = (hi + lo) / 2;
    centre = (middle / perDivision).round() * perDivision;
    // Keep zero on screen when it nearly is: a trace that starts at 0 V
    // should show its baseline.
    if ((centre - 3 * perDivision) > 0 && lo >= 0 && lo < perDivision * 2) {
      centre = 3 * perDivision;
    }
  }

  final List<double> values;
  final double window;
  final String unit;
  late final double perDivision;
  late double centre;

  static const int columns = 10;
  static const int rows = 6;

  double get top => centre + rows / 2 * perDivision;
  double get bottom => centre - rows / 2 * perDivision;
}

class ScopePainter extends CustomPainter {
  ScopePainter({required this.trace, required this.cursor, this.reveal = 1});

  final ScopeTrace trace;

  /// Sample index of the playback cursor.
  final int cursor;

  /// 0..1 fade-in of the trace when a run arrives.
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.2,
          colors: [Color(0xFF0F1F29), Color(0xFF081016)],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRRect(r);

    final w = size.width;
    final h = size.height;
    final grid = Paint()
      ..color = const Color(0xFF1C3140)
      ..strokeWidth = 1;
    for (var c = 1; c < ScopeTrace.columns; c++) {
      final x = w * c / ScopeTrace.columns;
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
    }
    for (var row = 1; row < ScopeTrace.rows; row++) {
      final y = h * row / ScopeTrace.rows;
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }
    // Centre graticule with minor ticks, as on a bench scope.
    final axis = Paint()
      ..color = const Color(0xFF2A4658)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), axis);
    canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), axis);
    for (var i = 0; i <= ScopeTrace.columns * 5; i++) {
      final x = w * i / (ScopeTrace.columns * 5);
      canvas.drawLine(Offset(x, h / 2 - 2.5), Offset(x, h / 2 + 2.5), axis);
    }

    final values = trace.values;
    if (values.length >= 2) {
      final path = Path();
      final visible = (values.length * reveal).clamp(2, values.length).toInt();
      double yOf(double v) =>
          h * (trace.top - v) / (trace.top - trace.bottom);
      for (var i = 0; i < visible; i++) {
        final x = w * i / (values.length - 1);
        final y = yOf(values[i]).clamp(-4.0, h + 4);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Bench.positive.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Bench.positive
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round,
      );

      // Playback cursor and the sample it points at.
      final ci = cursor.clamp(0, values.length - 1);
      final cx = w * ci / (values.length - 1);
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, h),
        Paint()
          ..color = Bench.charge.withValues(alpha: 0.55)
          ..strokeWidth = 1,
      );
      final cy = yOf(values[ci]).clamp(0.0, h);
      canvas.drawCircle(
          Offset(cx, cy),
          7,
          Paint()
            ..color = Bench.charge.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(Offset(cx, cy), 3.2, Paint()..color = Bench.charge);
    }
    canvas.restore();
    canvas.drawRRect(
      r,
      Paint()
        ..color = Bench.panelBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant ScopePainter old) =>
      old.trace != trace || old.cursor != cursor || old.reveal != reveal;
}

/// The scope with its readouts: what is probed, the value at the cursor,
/// the scales, and how much the playback is slowed down.
class ScopePanel extends StatelessWidget {
  const ScopePanel({
    super.key,
    required this.title,
    required this.trace,
    required this.cursor,
    required this.cursorTime,
    required this.slowdown,
    required this.onClose,
    this.hint,
  });

  final String title;
  final ScopeTrace trace;
  final int cursor;
  final double cursorTime;

  /// Circuit seconds per real second of playback.
  final double slowdown;
  final VoidCallback onClose;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final value = trace.values.isEmpty
        ? 0.0
        : trace.values[cursor.clamp(0, trace.values.length - 1)];
    const label = TextStyle(
        color: Bench.inkDim,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        fontFeatures: [FontFeature.tabularFigures()]);
    return Container(
      decoration: const BoxDecoration(
        color: Bench.panel,
        border: Border(top: BorderSide(color: Bench.panelBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: Bench.positive, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: label.copyWith(color: Bench.ink, fontSize: 13)),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(end: value),
                duration: const Duration(milliseconds: 120),
                builder: (context, v, _) => Text(
                  formatSi(v, trace.unit),
                  style: const TextStyle(
                    color: Bench.positive,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                color: Bench.inkDim,
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              height: 120,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(trace),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, reveal, _) => CustomPaint(
                  painter: ScopePainter(
                      trace: trace, cursor: cursor, reveal: reveal),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Text(
                    '${formatSi(trace.perDivision, trace.unit)}/div · '
                    '${formatSi(trace.window / ScopeTrace.columns, 's')}/div',
                    style: label),
                const Spacer(),
                Text('t = ${formatSi(cursorTime, 's')}', style: label),
                if (slowdown > 1.5) ...[
                  const SizedBox(width: 10),
                  Text(
                      tr(
                          zh: '慢放 ${_round(slowdown)}×',
                          en: '${_round(slowdown)}× slow-mo'),
                      style: label.copyWith(color: Bench.charge)),
                ],
              ],
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: label.copyWith(fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }

  static String _round(double x) {
    if (x >= 1e6) return '${(x / 1e6).toStringAsFixed(x >= 1e7 ? 0 : 1)}M';
    if (x >= 1e3) return '${(x / 1e3).toStringAsFixed(x >= 1e4 ? 0 : 1)}k';
    return x.toStringAsFixed(0);
  }
}
