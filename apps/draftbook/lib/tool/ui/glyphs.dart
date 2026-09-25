import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../haptics.dart';
import '../models.dart';
import 'widgets.dart';

/// Draftbook's own icons (kb/UIUX规矩.md 2.2: the core icons are drawn, in the
/// app's stroke — 1.5 units on a 24-unit square, square ends, mitred joins —
/// so they read as type-shop tools rather than Material defaults).
enum DbGlyph {
  settings,
  shelf,
  outline,
  nib,
  history,
  export,
  stats,
  plus,
  drag,
  asterism,
  quote,
  prev,
  next,
  keyboardDown,
  disclosure,
  close,
}

class DbIcon extends StatelessWidget {
  const DbIcon(this.glyph, {super.key, this.size = 24, this.color});

  final DbGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? DbColors.of(context).ink;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _GlyphPainter(glyph, c)),
      ),
    );
  }
}

/// A 48×48 icon button with a label for assistive tech, press scale and no
/// ripple.
class DbIconButton extends StatelessWidget {
  const DbIconButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final DbGlyph glyph;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        excludeSemantics: true,
        child: PressScale(
          enabled: enabled,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: SizedBox.square(
              dimension: DbSpace.iconButton,
              child: Center(
                child: DbIcon(
                  glyph,
                  color: enabled ? (color ?? c.ink) : c.ruleStrong,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final DbGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.shortestSide / 24;
    canvas.scale(u);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final fill = Paint()..color = color;

    switch (glyph) {
      case DbGlyph.settings:
        // Two composing-stick sliders.
        canvas
          ..drawLine(const Offset(3, 8), const Offset(12, 8), stroke)
          ..drawLine(const Offset(18, 8), const Offset(21, 8), stroke)
          ..drawRect(const Rect.fromLTWH(12.75, 5.5, 4.5, 5), stroke)
          ..drawLine(const Offset(3, 16), const Offset(6, 16), stroke)
          ..drawLine(const Offset(12, 16), const Offset(21, 16), stroke)
          ..drawRect(const Rect.fromLTWH(6.75, 13.5, 4.5, 5), stroke);
      case DbGlyph.shelf:
        // Two spines and a leaning third on a shelf.
        canvas
          ..drawRect(const Rect.fromLTWH(4, 6, 4, 14), stroke)
          ..drawRect(const Rect.fromLTWH(9.5, 4, 4, 16), stroke)
          ..drawLine(const Offset(2, 20.75), const Offset(22, 20.75), stroke);
        canvas.save();
        canvas.translate(15.5, 20);
        canvas.rotate(-0.36);
        canvas.drawRect(const Rect.fromLTWH(0, -14, 4, 14), stroke);
        canvas.restore();
      case DbGlyph.outline:
        // A table of contents: a chapter rule and two indented scenes.
        canvas
          ..drawLine(const Offset(3, 5.5), const Offset(21, 5.5), stroke)
          ..drawLine(const Offset(5, 5.5), const Offset(5, 17.5), stroke)
          ..drawLine(const Offset(5, 11.5), const Offset(9, 11.5), stroke)
          ..drawLine(const Offset(11, 11.5), const Offset(21, 11.5), stroke)
          ..drawLine(const Offset(5, 17.5), const Offset(9, 17.5), stroke)
          ..drawLine(const Offset(11, 17.5), const Offset(19, 17.5), stroke);
      case DbGlyph.nib:
        // A pen nib, tip down-left — the launcher icon's gesture.
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(math.pi / 4);
        canvas.translate(-12, -12);
        final nib = Path()
          ..moveTo(12, 22)
          ..lineTo(6.5, 12)
          ..lineTo(8, 4)
          ..lineTo(16, 4)
          ..lineTo(17.5, 12)
          ..close();
        canvas
          ..drawPath(nib, stroke)
          ..drawLine(const Offset(12, 22), const Offset(12, 14.5), stroke)
          ..drawCircle(const Offset(12, 12.5), 1.4, fill)
          ..drawLine(const Offset(8, 7.5), const Offset(16, 7.5), stroke);
        canvas.restore();
      case DbGlyph.history:
        // Proofs stacked: this version over the ones before it.
        canvas
          ..drawRect(const Rect.fromLTWH(8, 3.5, 12, 15), stroke)
          ..drawPath(
            Path()
              ..moveTo(5, 7)
              ..lineTo(5, 21.5)
              ..lineTo(16, 21.5),
            stroke,
          )
          ..drawLine(const Offset(11, 8), const Offset(17, 8), stroke)
          ..drawLine(const Offset(11, 11.5), const Offset(17, 11.5), stroke)
          ..drawLine(const Offset(11, 15), const Offset(15, 15), stroke);
      case DbGlyph.export:
        canvas
          ..drawPath(
            Path()
              ..moveTo(8.5, 10)
              ..lineTo(5, 10)
              ..lineTo(5, 21)
              ..lineTo(19, 21)
              ..lineTo(19, 10)
              ..lineTo(15.5, 10),
            stroke,
          )
          ..drawLine(const Offset(12, 3.5), const Offset(12, 15), stroke)
          ..drawPath(
            Path()
              ..moveTo(8.5, 7)
              ..lineTo(12, 3.5)
              ..lineTo(15.5, 7),
            stroke,
          );
      case DbGlyph.stats:
        // A line gauge: ticks of rising height.
        canvas.drawLine(const Offset(3, 20.25), const Offset(21, 20.25), stroke);
        for (final (x, h) in [(5.0, 5.0), (9.0, 9.0), (13.0, 7.0), (17.0, 13.0)]) {
          canvas.drawLine(Offset(x, 20.25), Offset(x, 20.25 - h), stroke);
        }
      case DbGlyph.plus:
        canvas
          ..drawLine(const Offset(12, 4), const Offset(12, 20), stroke)
          ..drawLine(const Offset(4, 12), const Offset(20, 12), stroke);
      case DbGlyph.drag:
        for (final y in [8.0, 12.0, 16.0]) {
          canvas.drawLine(Offset(5, y), Offset(19, y), stroke);
        }
      case DbGlyph.asterism:
        // ⁂ — the typesetter's scene break, drawn (Newsreader lacks it).
        void star(Offset o) {
          for (var i = 0; i < 3; i++) {
            final a = math.pi / 2 + i * math.pi / 3;
            final d = Offset(math.cos(a), math.sin(a)) * 3.2;
            canvas.drawLine(o - d, o + d, stroke..strokeWidth = 1.3);
          }
        }
        star(const Offset(12, 7));
        star(const Offset(7, 16));
        star(const Offset(17, 16));
      case DbGlyph.prev:
        canvas.drawPath(
          Path()
            ..moveTo(15, 5)
            ..lineTo(8, 12)
            ..lineTo(15, 19),
          stroke,
        );
      case DbGlyph.next:
        canvas.drawPath(
          Path()
            ..moveTo(9, 5)
            ..lineTo(16, 12)
            ..lineTo(9, 19),
          stroke,
        );
      case DbGlyph.disclosure:
        // Open state; the caller turns it a quarter for closed.
        canvas.drawPath(
          Path()
            ..moveTo(6, 9)
            ..lineTo(12, 15)
            ..lineTo(18, 9),
          stroke,
        );
      case DbGlyph.close:
        canvas
          ..drawLine(const Offset(6, 6), const Offset(18, 18), stroke)
          ..drawLine(const Offset(18, 6), const Offset(6, 18), stroke);
      case DbGlyph.keyboardDown:
        // A keyboard, and a caret pointing down under it.
        canvas.drawRect(const Rect.fromLTWH(3, 3.5, 18, 11), stroke);
        for (final x in [6.5, 10.0, 13.5, 17.0]) {
          canvas.drawLine(Offset(x, 7), Offset(x + 0.5, 7), stroke);
        }
        canvas
          ..drawLine(const Offset(8, 11), const Offset(16, 11), stroke)
          ..drawPath(
            Path()
              ..moveTo(9, 18)
              ..lineTo(12, 21)
              ..lineTo(15, 18),
            stroke,
          );
      case DbGlyph.quote:
        // A heavy opening quote, two teardrops.
        for (final x in [7.5, 15.5]) {
          canvas.drawCircle(Offset(x, 14), 3, fill);
          canvas.drawPath(
            Path()
              ..moveTo(x - 3, 14)
              ..quadraticBezierTo(x - 2.6, 7.5, x + 2.5, 5.5)
              ..lineTo(x + 2.8, 7)
              ..quadraticBezierTo(x - 0.5, 9, x, 11.2)
              ..close(),
            fill,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}

/// A scene's status as a mark whose *shape* carries the meaning, so it reads
/// in greyscale and to a screen reader: an empty ring (to write), a
/// half-inked ring (draft), a solid ink disc with a tick (done).
class StatusMark extends StatelessWidget {
  const StatusMark({super.key, required this.status, this.size = 14});

  final SceneStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    return Semantics(
      label: sceneStatusLabel(status),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _StatusPainter(
            status: status,
            ring: c.ruleStrong,
            draft: c.accent,
            done: c.ink,
            knock: c.page,
          ),
        ),
      ),
    );
  }
}

class _StatusPainter extends CustomPainter {
  _StatusPainter({
    required this.status,
    required this.ring,
    required this.draft,
    required this.done,
    required this.knock,
  });

  final SceneStatus status;
  final Color ring;
  final Color draft;
  final Color done;
  final Color knock;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final o = Offset(r, r);
    final w = math.max(1.4, r * 0.2);
    switch (status) {
      case SceneStatus.todo:
        canvas.drawCircle(
          o,
          r - w / 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..color = ring,
        );
      case SceneStatus.drafting:
        canvas
          ..drawCircle(
            o,
            r - w / 2,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = w
              ..color = draft,
          )
          ..drawArc(
            Rect.fromCircle(center: o, radius: r - w / 2),
            math.pi / 2,
            math.pi,
            true,
            Paint()..color = draft,
          );
      case SceneStatus.done:
        canvas.drawCircle(o, r, Paint()..color = done);
        canvas.drawPath(
          Path()
            ..moveTo(r * 0.52, r * 1.02)
            ..lineTo(r * 0.86, r * 1.36)
            ..lineTo(r * 1.5, r * 0.66),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..color = knock,
        );
    }
  }

  @override
  bool shouldRepaint(_StatusPainter old) =>
      old.status != status || old.ring != ring || old.draft != draft || old.done != done;
}

/// The book seen edge-on: one band per chapter, as thick as that chapter is
/// long. The chapter being written is inked in the accent and stands a third
/// taller than the rest, like a ribbon marker rising out of the fore-edge, so
/// it reads without colour too (kb F11). Real data, not decoration: a book
/// with one fat chapter and three thin ones looks it.
class ForeEdge extends StatelessWidget {
  const ForeEdge({
    super.key,
    required this.chapterWords,
    this.current,
    this.height = 12,
  });

  final List<int> chapterWords;
  final int? current;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _ForeEdgePainter(
            words: chapterWords,
            current: current,
            ink: c.ink,
            quiet: c.inkMuted,
            empty: c.rule,
            accent: c.accent,
          ),
        ),
      ),
    );
  }
}

class _ForeEdgePainter extends CustomPainter {
  _ForeEdgePainter({
    required this.words,
    required this.current,
    required this.ink,
    required this.quiet,
    required this.empty,
    required this.accent,
  });

  final List<int> words;
  final int? current;
  final Color ink;
  final Color quiet;
  final Color empty;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (words.isEmpty || size.width <= 0) return;
    const gap = 2.0;
    const minBand = 3.0;
    final total = words.fold<int>(0, (a, b) => a + b);
    final usable = size.width - gap * (words.length - 1);
    // Every chapter gets at least a sliver; the rest is shared by length.
    final share = math.max(0.0, usable - minBand * words.length);
    // Only the current chapter uses the full height; with no current chapter
    // every band does, so nothing looks marked.
    final rest = current == null ? 0.0 : size.height / 3;
    var x = 0.0;
    for (var i = 0; i < words.length; i++) {
      final w = minBand + (total == 0 ? share / words.length : share * words[i] / total);
      final color = i == current
          ? accent
          : words[i] == 0
              ? empty
              : (i.isEven ? ink : quiet);
      final top = i == current ? 0.0 : rest;
      canvas.drawRect(Rect.fromLTWH(x, top, w, size.height - top), Paint()..color = color);
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(_ForeEdgePainter old) =>
      old.current != current ||
      old.ink != ink ||
      old.accent != accent ||
      old.words.length != words.length ||
      !_same(old.words, words);

  static bool _same(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Selection feedback + the handler, for chips and segmented choices.
VoidCallback selecting(VoidCallback f) => () {
      Haptics.select();
      f();
    };
