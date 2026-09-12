import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';

/// The app's own graphic language: six bold-stroke glyphs, one per tool,
/// drawn (not iconfont) so the home board, the tool header and the launcher
/// icon all speak the same hand. Each is composed in a unit square with
/// round caps and a stroke of ~11% of the size.
class ToolGlyph extends StatelessWidget {
  const ToolGlyph({
    super.key,
    required this.kind,
    required this.color,
    this.size = 32,
    this.strokeScale = 1,
  });
  final ToolKind kind;
  final Color color;
  final double size;
  final double strokeScale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GlyphPainter(kind, color, strokeScale),
      ),
    );
  }
}

/// Hero tag shared by the home board tile and the tool page header.
String toolHeroTag(ToolKind k) => 'picbox-tool-${k.name}';

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind, this.color, this.strokeScale);
  final ToolKind kind;
  final Color color;
  final double strokeScale;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.11 * strokeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset o(double x, double y) => Offset(x * s, y * s);
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(o(x1, y1), o(x2, y2), p);
    void poly(List<(double, double)> pts) {
      final path = Path()..moveTo(pts.first.$1 * s, pts.first.$2 * s);
      for (final (x, y) in pts.skip(1)) {
        path.lineTo(x * s, y * s);
      }
      canvas.drawPath(path, p);
    }

    switch (kind) {
      case ToolKind.compress:
        // Two chevrons squeezing a bar.
        poly([(0.28, 0.16), (0.5, 0.36), (0.72, 0.16)]);
        poly([(0.28, 0.84), (0.5, 0.64), (0.72, 0.84)]);
        line(0.3, 0.5, 0.7, 0.5);
      case ToolKind.resize:
        // Diagonal double-headed arrow between two corner brackets.
        line(0.3, 0.7, 0.7, 0.3);
        poly([(0.48, 0.3), (0.7, 0.3), (0.7, 0.52)]);
        poly([(0.52, 0.7), (0.3, 0.7), (0.3, 0.48)]);
        poly([(0.16, 0.42), (0.16, 0.16), (0.42, 0.16)]);
        poly([(0.84, 0.58), (0.84, 0.84), (0.58, 0.84)]);
      case ToolKind.convert:
        // Two arcs chasing each other, each with an arrowhead.
        final r = 0.3 * s;
        final rect = Rect.fromCircle(center: o(0.5, 0.5), radius: r);
        canvas.drawArc(rect, _deg(200), _deg(130), false, p);
        canvas.drawArc(rect, _deg(20), _deg(130), false, p);
        // arrowheads at arc ends (330° and 150°)
        final a1 = o(0.5, 0.5) + Offset(math.cos(_deg(330)), math.sin(_deg(330))) * r;
        final a2 = o(0.5, 0.5) + Offset(math.cos(_deg(150)), math.sin(_deg(150))) * r;
        canvas.drawPath(
          Path()
            ..moveTo(a1.dx - 0.16 * s, a1.dy - 0.02 * s)
            ..lineTo(a1.dx, a1.dy)
            ..lineTo(a1.dx - 0.04 * s, a1.dy + 0.16 * s),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(a2.dx + 0.16 * s, a2.dy + 0.02 * s)
            ..lineTo(a2.dx, a2.dy)
            ..lineTo(a2.dx + 0.04 * s, a2.dy - 0.16 * s),
          p,
        );
      case ToolKind.crop:
        // The classic crop mark: two interlocking L's.
        poly([(0.3, 0.12), (0.3, 0.7), (0.88, 0.7)]);
        poly([(0.12, 0.3), (0.7, 0.3), (0.7, 0.88)]);
      case ToolKind.metadata:
        // Shield with a check: the picture is clean.
        final path = Path()
          ..moveTo(0.5 * s, 0.14 * s)
          ..lineTo(0.8 * s, 0.26 * s)
          ..lineTo(0.8 * s, 0.5 * s)
          ..quadraticBezierTo(0.8 * s, 0.74 * s, 0.5 * s, 0.86 * s)
          ..quadraticBezierTo(0.2 * s, 0.74 * s, 0.2 * s, 0.5 * s)
          ..lineTo(0.2 * s, 0.26 * s)
          ..close();
        canvas.drawPath(path, p);
        poly([(0.38, 0.5), (0.47, 0.6), (0.64, 0.4)]);
      case ToolKind.watermark:
        // A six-point star — the mark that gets stamped on.
        for (var i = 0; i < 3; i++) {
          final a = _deg(i * 60.0);
          final d = Offset(math.cos(a), math.sin(a)) * 0.32 * s;
          canvas.drawLine(o(0.5, 0.5) - d, o(0.5, 0.5) + d, p);
        }
        canvas.drawCircle(o(0.5, 0.5), s * 0.07, Paint()..color = color);
    }
  }

  static double _deg(double d) => d * math.pi / 180;

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.kind != kind || old.color != color || old.strokeScale != strokeScale;
}
