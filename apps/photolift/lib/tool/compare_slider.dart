import 'dart:io';

import 'package:flutter/material.dart';

import '../core/l10n.dart';

/// Before/after comparison: the result fills the box, the original is
/// clipped to the left of a draggable divider. Both images are drawn with
/// the same `BoxFit.contain` geometry so a 2x/4x result lines up pixel-for-
/// pixel over its source.
class CompareSlider extends StatefulWidget {
  const CompareSlider({
    super.key,
    required this.before,
    required this.after,
    required this.aspectRatio,
    this.initialFraction = 0.5,
    this.autoSweep = false,
    this.onSweepEnd,
  });

  final File before;
  final File after;
  /// width / height of the images.
  final double aspectRatio;
  final double initialFraction;
  /// On first build, sweep the divider left → right over the whole photo and
  /// settle at [initialFraction] (1.2 s) — a guided "look what changed"
  /// before the user touches it. A touch interrupts it. Skipped when the
  /// platform asks for reduced motion.
  final bool autoSweep;
  final VoidCallback? onSweepEnd;

  @override
  State<CompareSlider> createState() => _CompareSliderState();
}

class _CompareSliderState extends State<CompareSlider>
    with SingleTickerProviderStateMixin {
  late double _fraction = widget.autoSweep ? 0.0 : widget.initialFraction;
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final Animation<double> _sweepPos = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 62,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: widget.initialFraction)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 38,
    ),
  ]).animate(_sweep);
  bool _sweepScheduled = false;

  @override
  void initState() {
    super.initState();
    _sweepPos.addListener(() {
      if (mounted) setState(() => _fraction = _sweepPos.value);
    });
    _sweep.addStatusListener((st) {
      if (st == AnimationStatus.completed) widget.onSweepEnd?.call();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.autoSweep && !_sweepScheduled) {
      _sweepScheduled = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _fraction = widget.initialFraction;
        widget.onSweepEnd?.call();
      } else {
        // Let the images decode a frame before moving the divider.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sweep.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  void _update(Offset local, double width) {
    if (_sweep.isAnimating) {
      _sweep.stop();
      widget.onSweepEnd?.call();
    }
    setState(() => _fraction = (local.dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      // Decode at roughly the on-screen size — the result may be 24 MP.
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cacheW = (width * dpr).round();
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _update(d.localPosition, width),
        onHorizontalDragStart: (d) => _update(d.localPosition, width),
        onHorizontalDragUpdate: (d) => _update(d.localPosition, width),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ColoredBox(
            color: cs.surfaceContainerHighest,
            child: AspectRatio(
              aspectRatio: widget.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(widget.after, fit: BoxFit.contain, cacheWidth: cacheW,
                      gaplessPlayback: true),
                  ClipRect(
                    clipper: _LeftClipper(_fraction),
                    child: Image.file(widget.before, fit: BoxFit.contain, cacheWidth: cacheW,
                        gaplessPlayback: true),
                  ),
                  _Label(tr(zh: '原图', en: 'Before'), alignment: Alignment.topLeft),
                  _Label(tr(zh: '修复后', en: 'After'), alignment: Alignment.topRight),
                  Positioned(
                    left: _fraction * width - 1.5,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 3, color: Colors.white),
                  ),
                  Positioned(
                    left: _fraction * width - 22,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3)),
                          ],
                        ),
                        child: Icon(Icons.compare_arrows_rounded,
                            color: cs.primary, size: 26),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  const _LeftClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.fraction != fraction;
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.alignment});
  final String text;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
