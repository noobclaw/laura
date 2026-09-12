import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'tool_glyph.dart';
import 'widgets.dart';

/// PicWorks' signature hero: a 3×2 "tool board" — one plate, six tiles, each
/// tile a bold self-drawn glyph. On first show the tiles flip up one after
/// another (3D rotationY, 70 ms stagger); afterwards a random tile gives a
/// small hop every 8 s so the board feels alive. Tapping a tile opens the
/// tool; the tile's glyph is a [Hero] that flies into the tool page header.
/// Honours `MediaQuery.disableAnimations` (no flip, no hop).
class ToolBoard extends StatefulWidget {
  const ToolBoard({super.key, required this.onOpen});
  final ValueChanged<ToolKind> onOpen;

  @override
  State<ToolBoard> createState() => _ToolBoardState();
}

class _ToolBoardState extends State<ToolBoard> with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _stagger = Duration(milliseconds: 70);
  static const _flip = Duration(milliseconds: 460);
  static const _hopEvery = Duration(seconds: 8);

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: _flip + _stagger * (ToolKind.values.length - 1),
  );
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  // One curved view per tile, built once — not a fresh CurvedAnimation per
  // frame inside the builder.
  late final List<Animation<double>> _flips = [
    for (var i = 0; i < ToolKind.values.length; i++) _flipFor(i),
  ];
  final _rng = math.Random();
  Timer? _hopTimer;
  int _hopIndex = -1;
  bool _started = false;
  bool _reduced = false;
  // The hop ticker runs only while the board is actually on screen: not
  // under a pushed route (TickerMode off) and not while the app is in the
  // background (lifecycle paused).
  bool _tickerOn = true;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    final tickerOn = TickerMode.valuesOf(context).enabled;
    if (_started && reduced == _reduced && tickerOn == _tickerOn) return;
    _started = true;
    _reduced = reduced;
    _tickerOn = tickerOn;
    if (reduced) {
      _intro.value = 1;
    } else if (_intro.value == 0) {
      _intro.forward();
    }
    _syncHopTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active == _appActive) return;
    _appActive = active;
    _syncHopTimer();
  }

  /// Start or stop the periodic hop to match the current gates.
  void _syncHopTimer() {
    final want = !_reduced && _tickerOn && _appActive;
    if (want && _hopTimer == null) {
      _hopTimer = Timer.periodic(_hopEvery, (_) => _hopOne());
    } else if (!want && _hopTimer != null) {
      _hopTimer!.cancel();
      _hopTimer = null;
    }
  }

  void _hopOne() {
    if (!mounted || _hop.isAnimating) return;
    setState(() => _hopIndex = _rng.nextInt(ToolKind.values.length));
    _hop.forward(from: 0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hopTimer?.cancel();
    _intro.dispose();
    _hop.dispose();
    super.dispose();
  }

  /// Flip progress for tile [i]: 0 = face down, 1 = flat.
  Animation<double> _flipFor(int i) {
    final total = _intro.duration!.inMilliseconds.toDouble();
    final start = (_stagger.inMilliseconds * i) / total;
    final end = (_stagger.inMilliseconds * i + _flip.inMilliseconds) / total;
    return CurvedAnimation(
      parent: _intro,
      curve: Interval(start, end, curve: Curves.easeOutBack),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Tile labels are FittedBox-scaled and the glyph plate is fixed-size; past
    // ~1.3× the board would clip, so cap text scaling for the board only.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: _board(cs, dark),
    );
  }

  Widget _board(ColorScheme cs, bool dark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: dark ? cs.surfaceContainerLow : cs.surfaceContainerHigh,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: ToolColors.compress.withValues(alpha: dark ? 0.10 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          const gap = 10.0;
          final tile = (c.maxWidth - gap * 2) / 3;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final (i, k) in ToolKind.values.indexed)
                AnimatedBuilder(
                  animation: Listenable.merge([_intro, _hop]),
                  builder: (context, child) {
                    final f = _flips[i].value.clamp(0.0, 1.0);
                    final hopping = _hopIndex == i && _hop.isAnimating;
                    final h = hopping ? _hop.value : 0.0;
                    // Hop: a quick rise and settle, with a whisper of tilt.
                    final lift = math.sin(h * math.pi) * 8;
                    final tilt = math.sin(h * math.pi * 2) * 0.05;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0016)
                        ..rotateY((1 - f) * math.pi / 2)
                        ..translateByDouble(0.0, -lift, 0.0, 1.0)
                        ..rotateZ(tilt),
                      child: Opacity(opacity: f, child: child),
                    );
                  },
                  // Each tile repaints on its own layer: a hop or flip on one
                  // tile must not repaint the other five.
                  child: RepaintBoundary(
                    child: _Tile(
                      meta: ToolMeta.of(k),
                      size: tile,
                      onTap: () => widget.onOpen(k),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({required this.meta, required this.size, required this.onTap});
  final ToolMeta meta;
  final double size;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final m = widget.meta;
    final glyph = widget.size * 0.4;
    return AnimatedScale(
      scale: _down ? 0.94 : 1,
      duration: Motion.of(context, Motion.fast),
      curve: Curves.easeOut,
      child: Semantics(
        button: true,
        label: '${m.title}, ${m.subtitle}',
        child: Tooltip(
          message: m.subtitle,
          waitDuration: const Duration(milliseconds: 600),
          child: Material(
            color: dark ? cs.surfaceContainerHigh : cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (v) => setState(() => _down = v),
              splashColor: m.color.withValues(alpha: 0.18),
              highlightColor: m.color.withValues(alpha: 0.08),
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Hero(
                      tag: toolHeroTag(m.kind),
                      child: Container(
                        width: glyph + 20,
                        height: glyph + 20,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: m.color.withValues(alpha: dark ? 0.22 : 0.14),
                        ),
                        alignment: Alignment.center,
                        child: ToolGlyph(kind: m.kind, color: m.color, size: glyph),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          m.title,
                          maxLines: 1,
                          style: text.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
