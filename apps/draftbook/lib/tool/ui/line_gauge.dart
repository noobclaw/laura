import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../haptics.dart';
import '../models.dart';

/// Draftbook's signature scene (PLAN.md 设计简报 9): a compositor's **line
/// gauge** — the ruler a typesetter measured lines with — on which today's
/// words are set in ink.
///
/// Driven by real data only: [words] is `store.todayWords`, [goal] is the
/// daily goal. Each time the gauge appears it sets the ink from the count the
/// writer last saw to the count now, so coming back from the editor shows
/// exactly the run just written. Ticks the ink has passed darken; the goal is
/// a proofreader's caret (‸) that fills with the accent once reached, and the
/// first crossing of the day gives one medium haptic. Past the goal the ruler
/// rescales so the run always fits.
///
/// Reduced motion: drawn at its end state, no run, no moving caret.
class LineGauge extends StatefulWidget {
  const LineGauge({super.key, required this.words, required this.goal, this.caption});

  final int words;
  final int goal;

  /// When set, the figure (today's words, rolling with the ink) is set above
  /// the ruler with this caption beside it — one animation drives both.
  final String? caption;

  /// What the writer last saw today, so the next appearance runs from there.
  static int _lastSeen = 0;
  static String _lastSeenDay = '';

  /// Tests and the screenshot harness start every run from a blank day.
  static void resetMemory() {
    _lastSeen = 0;
    _lastSeenDay = '';
    Haptics.resetMilestone();
  }

  @override
  State<LineGauge> createState() => _LineGaugeState();
}

class _LineGaugeState extends State<LineGauge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: DbMotion.hero)
    ..addListener(_checkMilestone);
  late final CurvedAnimation _curve = CurvedAnimation(parent: _c, curve: DbMotion.enter);
  double _from = 0;
  bool _started = false;

  String get _today => dayKey(DateTime.now());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final seen = LineGauge._lastSeenDay == _today ? LineGauge._lastSeen : 0;
    _from = math.min(seen, widget.words).toDouble();
    _run();
  }

  @override
  void didUpdateWidget(covariant LineGauge old) {
    super.didUpdateWidget(old);
    if (old.words != widget.words || old.goal != widget.goal) {
      _from = _value;
      _run();
    }
  }

  void _run() {
    LineGauge._lastSeen = widget.words;
    LineGauge._lastSeenDay = _today;
    if (DbMotion.reduced(context) || _from == widget.words) {
      _c.value = 1;
      _checkMilestone();
    } else {
      _c.forward(from: 0);
    }
  }

  double get _value => _from + (widget.words - _from) * _curve.value;

  void _checkMilestone() {
    final g = widget.goal;
    if (g <= 0 || _value < g || _from >= g) return;
    // Once per day, across launches: the day is kept on disk by Haptics.
    Haptics.milestoneOnce(_today);
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    // Tick numerals may grow with the reader's text size, capped at 1.5×
    // (kb F10 allows the hero figure its own cap) so the ruler keeps a scale.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5);
    final label = DbType.numeral.copyWith(color: c.inkMuted);
    final labelHeight = scaler.scale(label.fontSize!) * label.height!;
    final g = widget.goal;
    return Semantics(
      label: g > 0
          ? tr(
              zh: '今天 ${groupedCount(widget.words)} 字，目标 ${groupedCount(g)} 字',
              en: 'Today, ${groupedCount(widget.words)} of ${groupedCount(g)} words',
            )
          : tr(zh: '今天 ${groupedCount(widget.words)} 字', en: 'Today, ${groupedCount(widget.words)} words'),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.caption != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => Text(
                    groupedCount(_value.round()),
                    // The hero figure may cap its own growth at 1.5× (kb F10).
                    textScaler: scaler,
                    style: DbType.figure.copyWith(color: c.ink),
                  ),
                ),
                const SizedBox(width: DbSpace.x1_5),
                Flexible(
                  child: Text(
                    widget.caption!,
                    style: DbType.byline.copyWith(color: c.inkMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DbSpace.x1),
          ],
          _gauge(c, scaler, label, labelHeight, g),
        ],
      ),
    );
  }

  Widget _gauge(DbColors c, TextScaler scaler, TextStyle label, double labelHeight, int g) {
    return RepaintBoundary(
        child: SizedBox(
          height: 34 + labelHeight + DbSpace.x0_5,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _GaugePainter(
                value: _value,
                goal: g,
                ink: c.ink,
                rule: c.rule,
                tick: c.ruleStrong,
                accent: c.accent,
                label: label,
                scaler: scaler,
              ),
            ),
          ),
        ),
      );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.goal,
    required this.ink,
    required this.rule,
    required this.tick,
    required this.accent,
    required this.label,
    required this.scaler,
  });

  final double value;
  final int goal;
  final Color ink;
  final Color rule;
  final Color tick;
  final Color accent;
  final TextStyle label;
  final TextScaler scaler;

  static const List<int> _steps = [
    50, 100, 200, 250, 500, 1000, 2000, 2500, 5000, 10000, 20000, 25000, 50000, 100000,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final reach = math.max(goal > 0 ? goal.toDouble() : 500.0, value * 1.06);
    var step = _steps.last;
    for (final s in _steps) {
      if (reach / s <= 5) {
        step = s;
        break;
      }
    }
    final span = (reach / step).ceil() * step;
    final majors = span ~/ step;

    TextPainter layout(String s) => TextPainter(
          text: TextSpan(text: s, style: label),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();

    final last = layout(groupedCount(span));
    final inset = last.width / 2;
    const left = 0.0;
    final right = size.width - inset;
    double x(double w) => left + (right - left) * (w / span);

    final base = size.height - last.height - 6;
    last.dispose();
    const majorH = 12.0;
    const minorH = 5.0;
    final head = x(value.clamp(0, span.toDouble()));

    // The hairline the type sits on.
    canvas.drawLine(Offset(left, base), Offset(size.width, base),
        Paint()..color = rule..strokeWidth = DbRadius.hairline);

    // Ticks: five per major; the ones the ink has passed are inked.
    final tickPaint = Paint()..strokeWidth = DbRadius.hairline;
    for (var i = 0; i <= majors * 5; i++) {
      final w = step * i / 5;
      final tx = x(w);
      final major = i % 5 == 0;
      tickPaint.color = tx <= head ? ink : tick;
      canvas.drawLine(Offset(tx, base), Offset(tx, base - (major ? majorH : minorH)), tickPaint);
      if (major) {
        final tp = layout(groupedCount(w.round()));
        final lx = i == 0 ? tx : math.min(tx - tp.width / 2, size.width - tp.width);
        tp.paint(canvas, Offset(lx, base + 4));
        tp.dispose();
      }
    }

    // The run of ink: today's words.
    if (head > left) {
      canvas.drawRect(Rect.fromLTRB(left, base - 1.5, head, base + 1.5), Paint()..color = accent);
    }

    // The goal: a proofreader's caret above the ruler.
    if (goal > 0) {
      final gx = x(goal.toDouble());
      final reached = value >= goal;
      final top = base - majorH - 12;
      final caret = Path()
        ..moveTo(gx - 5, top + 8)
        ..lineTo(gx, top)
        ..lineTo(gx + 5, top + 8);
      if (reached) caret.close();
      canvas.drawPath(
        caret,
        Paint()
          ..color = reached ? accent : ink
          ..style = reached ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // The type cursor riding the head of the run.
    canvas.drawRect(Rect.fromLTWH(head - 1, base - majorH - 6, 2, majorH + 8), Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value ||
      old.goal != goal ||
      old.ink != ink ||
      old.accent != accent ||
      old.scaler != scaler;
}
