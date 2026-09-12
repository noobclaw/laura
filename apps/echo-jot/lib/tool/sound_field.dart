import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// EchoJot's signature graphic: a ring of spectrum bars around the mic button.
///
/// While a session is live each bar bounces to the recogniser's rolling
/// loudness history ([levels], newest last): the newest sample sits at twelve
/// o'clock and older ones fan down both sides, so speech reads as a ripple
/// travelling around the ring. Idle, the ring breathes at a very low amplitude
/// so the hero never looks dead. Everything is drawn in one [CustomPainter]
/// inside a [RepaintBoundary]; per-bar smoothing runs off a single ticker so a
/// 27-sample history at 10 Hz still animates at frame rate.
class SoundField extends StatefulWidget {
  const SoundField({
    super.key,
    required this.levels,
    required this.active,
    required this.child,
    this.size = defaultSize,
    this.bars = 56,
  });

  /// Ring side on a tall phone.
  static const double defaultSize = 212;

  /// Smallest ring that still clears the 96dp mic button (see [minInner]).
  static const double minSize = 160;

  /// Bars never start inside the mic button's 48dp radius, however small the
  /// ring is scaled on a short screen.
  static const double minInner = 50;

  /// Rolling loudness 0..1, oldest first (DictationController.levels).
  final List<double> levels;

  /// True while a microphone is open — switches from breathing to bouncing.
  final bool active;

  /// Drawn in the centre of the ring (the mic button).
  final Widget child;

  /// Side of the square the ring is drawn in.
  final double size;

  /// Number of bars around the ring (48–64 reads as a field, not spokes).
  final int bars;

  @override
  State<SoundField> createState() => _SoundFieldState();
}

class _SoundFieldState extends State<SoundField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    // One full breathing cycle; the bounce smoothing just rides this ticker.
    duration: const Duration(seconds: 4),
  );

  /// Displayed bar energies (0..1), eased towards the target each frame so
  /// the ring never snaps between level samples. Shared with the painter by
  /// reference: the ticker mutates it and asks only the CustomPaint to
  /// repaint — the mic button in the centre is never rebuilt per frame.
  late final _FieldModel _model = _FieldModel(widget.bars);
  late List<double> _target = List<double>.filled(widget.bars, 0);
  Duration _last = Duration.zero;
  bool _reduceMotion = false;

  List<double> get _shown => _model.shown;
  double get _activeMix => _model.activeMix;
  set _activeMix(double v) => _model.activeMix = v;

  @override
  void initState() {
    super.initState();
    _target = _targetsFor(widget.levels);
    _shown.setAll(0, _target);
    _activeMix = widget.active ? 1 : 0;
    _clock.addListener(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SoundField old) {
    super.didUpdateWidget(old);
    if (old.bars != widget.bars) {
      _model.reset(widget.bars);
    }
    _target = _targetsFor(widget.levels);
    if (_reduceMotion) {
      // No ticker: land on the final state immediately.
      _shown.setAll(0, _target);
      _activeMix = widget.active ? 1 : 0;
      _model.notify();
    }
  }

  @override
  void dispose() {
    _clock.removeListener(_tick);
    _clock.dispose();
    _model.dispose();
    super.dispose();
  }

  /// Maps the level history onto the ring: bar 0 at the top, mirrored so the
  /// left and right halves show the same ripple.
  List<double> _targetsFor(List<double> levels) {
    final n = widget.bars;
    final out = List<double>.filled(n, 0);
    if (levels.isEmpty) return out;
    final half = n / 2;
    for (var i = 0; i < n; i++) {
      // 0 at twelve o'clock, growing to `half` at six o'clock on either side.
      final d = i <= half ? i.toDouble() : n - i.toDouble();
      final pos = 1 - d / half; // 1 = newest (top), 0 = oldest (bottom)
      final idx = (pos * (levels.length - 1)).round().clamp(
        0,
        levels.length - 1,
      );
      out[i] = levels[idx].clamp(0.0, 1.0);
    }
    return out;
  }

  void _tick() {
    final now = _clock.lastElapsedDuration ?? Duration.zero;
    var dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0 || dt > 0.25) dt = 1 / 60;
    // Attack faster than release: a syllable pops, then the ring relaxes.
    for (var i = 0; i < _shown.length; i++) {
      final t = _target[i];
      final s = _shown[i];
      final k = t > s ? 18.0 : 7.0;
      _shown[i] = s + (t - s) * (1 - math.exp(-k * dt));
    }
    final mixTarget = widget.active ? 1.0 : 0.0;
    if ((mixTarget - _activeMix).abs() > 0.001) {
      _activeMix += (mixTarget - _activeMix) * (1 - math.exp(-6 * dt));
    }
    // No setState: the painter repaints off the clock itself, so only the
    // CustomPaint layer redraws each frame — the mic button is left alone.
  }

  /// Kept across rebuilds (the home page rebuilds every second while
  /// recording) so the painter's colour tables and shader cache survive;
  /// replaced only when the theme or the motion setting changes.
  _SoundFieldPainter? _painter;

  _SoundFieldPainter _painterFor(EchoJotColors colors) {
    final p = _painter;
    final breathe = !_reduceMotion;
    if (p != null &&
        p.breathe == breathe &&
        p.idle == colors.fieldIdle &&
        p.live == colors.live &&
        p.glow == colors.fieldGlow) {
      return p;
    }
    return _painter = _SoundFieldPainter(
      model: _model,
      clock: _clock,
      breathe: breathe,
      idle: colors.fieldIdle,
      live: colors.live,
      glow: colors.fieldGlow,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = EchoJotColors.of(context);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _painterFor(colors),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

/// Mutable per-frame state shared between the ticker and the painter.
class _FieldModel extends ChangeNotifier {
  _FieldModel(int bars) : shown = List<double>.filled(bars, 0);

  List<double> shown;
  double activeMix = 0; // 0 = idle look, 1 = live look (cross-faded)

  void reset(int bars) {
    shown = List<double>.filled(bars, 0);
  }

  void notify() => notifyListeners();
}

class _SoundFieldPainter extends CustomPainter {
  _SoundFieldPainter({
    required this.model,
    required this.clock,
    required this.breathe,
    required this.idle,
    required this.live,
    required this.glow,
  }) : super(repaint: Listenable.merge([model, clock]));

  final _FieldModel model;
  final AnimationController clock;
  final bool breathe;
  final Color idle;
  final Color live;
  final Color glow;

  // This paints at frame rate for as long as the hero is on screen, so
  // nothing below allocates per frame in the steady states: paints are fields,
  // bar colours come from two small lookup tables (idle by breathing phase,
  // live by energy), and the glow shader is rebuilt only when the ring size
  // or the quantised cross-fade step changes.
  static const _steps = 32;

  late final List<Color> _idleTable = List<Color>.generate(
    _steps + 1,
    (i) => idle.withValues(alpha: 0.55 + (i / _steps) * 0.25),
  );
  late final List<Color> _liveTable = List<Color>.generate(
    _steps + 1,
    (i) => Color.lerp(live.withValues(alpha: 0.45), live, i / _steps)!,
  );

  final Paint _barPaint = Paint()
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final Paint _glowPaint = Paint();
  double _glowOuter = -1;
  int _glowStep = -1;

  static int _q(double v) => (v.clamp(0.0, 1.0) * _steps).round();

  @override
  void paint(Canvas canvas, Size size) {
    final energies = model.shown;
    final activeMix = model.activeMix;
    final phase = breathe ? clock.value : 0.0; // 0..1, one breathing cycle
    final c = size.center(Offset.zero);
    final n = energies.length;
    if (n == 0) return;
    final outer = size.shortestSide / 2;
    // The mic button is 96dp; bars start just outside its pulse ring, and
    // never inside the button when the ring is scaled down on a short screen.
    final inner = math.max(outer * 0.56, SoundField.minInner);
    final maxLen = outer - inner - 2;
    final barW = (2 * math.pi * inner / n) * 0.48;

    if (activeMix > 0.01) {
      final step = _q(activeMix);
      if (step != _glowStep || outer != _glowOuter) {
        _glowStep = step;
        _glowOuter = outer;
        _glowPaint.shader = RadialGradient(
          colors: [
            glow.withValues(alpha: glow.a * (step / _steps)),
            glow.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: outer));
      }
      canvas.drawCircle(c, outer, _glowPaint);
    }

    final paint = _barPaint..strokeWidth = barW;
    // Fully idle / fully live (the two steady states) read straight from the
    // tables; only the ~half-second cross-fade between them lerps.
    final idleOnly = activeMix <= 0.01;
    final liveOnly = activeMix >= 0.99;

    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i) / n;
      // Idle: a slow wave travelling around the ring, 2–4 px tall.
      final wave = breathe
          ? 0.5 + 0.5 * math.sin(2 * math.pi * phase - angle * 2)
          : 0.5;
      final idleLen = 3.0 + wave * 5.0;
      // Live: bar length from the smoothed energy, with a floor so silence is
      // a crisp thin ring rather than nothing.
      final e = energies[i];
      final liveLen = 4.0 + e * maxLen;
      final len = idleLen + (liveLen - idleLen) * activeMix;

      final idleColor = _idleTable[_q(wave)];
      final liveColor = _liveTable[_q(e)];
      paint.color = idleOnly
          ? idleColor
          : liveOnly
          ? liveColor
          : Color.lerp(idleColor, liveColor, activeMix)!;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(c + dir * inner, c + dir * (inner + len), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SoundFieldPainter old) =>
      old.model != model ||
      old.clock != clock ||
      old.breathe != breathe ||
      old.idle != idle ||
      old.live != live ||
      old.glow != glow;
}
