import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format.dart';
import '../schematic/document.dart';
import '../sim/flow.dart';
import '../sim/simulation.dart';
import 'lab_theme.dart';

/// Where the drawing sits on screen: `screen = grid * scale + offset`.
@immutable
class CanvasView {
  const CanvasView({this.offset = Offset.zero, this.scale = 32});

  final Offset offset;

  /// Pixels per grid cell.
  final double scale;

  static const double minScale = 10;
  static const double maxScale = 80;

  Offset toScreen(GridPoint p) =>
      Offset(p.x * scale + offset.dx, p.y * scale + offset.dy);

  Offset toScreenXY(double gx, double gy) =>
      Offset(gx * scale + offset.dx, gy * scale + offset.dy);

  Offset toGrid(Offset screen) =>
      Offset((screen.dx - offset.dx) / scale, (screen.dy - offset.dy) / scale);

  CanvasView copyWith({Offset? offset, double? scale}) =>
      CanvasView(offset: offset ?? this.offset, scale: scale ?? this.scale);

  /// A view that frames [doc] inside [size] with a margin of cells.
  static CanvasView fit(SchematicDocument doc, Size size,
      {double margin = 2.5, double maxScale = 46}) {
    final bounds = documentBounds(doc);
    if (bounds == null || size.isEmpty) {
      return CanvasView(offset: Offset(size.width / 2, size.height / 2));
    }
    final w = bounds.width + margin * 2;
    final h = bounds.height + margin * 2;
    final scale = math
        .min(size.width / w, size.height / h)
        .clamp(minScale * 0.5, maxScale)
        .toDouble();
    final center = bounds.center;
    return CanvasView(
      scale: scale,
      offset: Offset(size.width / 2 - center.dx * scale,
          size.height / 2 - center.dy * scale),
    );
  }
}

/// Grid-unit bounding box of everything drawn, or null for an empty canvas.
Rect? documentBounds(SchematicDocument doc) {
  double? l, t, r, b;
  void take(GridPoint p) {
    l = l == null ? p.x.toDouble() : math.min(l!, p.x.toDouble());
    t = t == null ? p.y.toDouble() : math.min(t!, p.y.toDouble());
    r = r == null ? p.x.toDouble() : math.max(r!, p.x.toDouble());
    b = b == null ? p.y.toDouble() : math.max(b!, p.y.toDouble());
  }

  for (final p in doc.parts) {
    p.pins.forEach(take);
    // Ground symbols hang below their pin.
    if (p.kind == PartKind.ground) take(p.origin.translate(0, 1));
  }
  for (final w in doc.wires) {
    take(w.from);
    take(w.to);
  }
  if (l == null) return null;
  return Rect.fromLTRB(l!, t!, r!, b!);
}

/// A live simulation frame as the painter needs it.
class RunFrame {
  const RunFrame({
    required this.run,
    required this.sample,
    required this.segmentCurrents,
    required this.flow,
    required this.chargeOffsets,
  });

  final SimRun run;
  final int sample;
  final List<double> segmentCurrents;
  final FlowGraph flow;

  /// How far the charge on each element has travelled, in grid units:
  /// `p:<partId>` and `s:<segmentIndex>`.
  final Map<String, double> chargeOffsets;
}

/// Speed of charge along an element in grid cells per second, signed along
/// the element's direction. Square-root scaled so that a branch carrying a
/// hundredth of the peak current still visibly moves.
double chargeSpeed(double amps, double peakAmps) {
  if (peakAmps <= 1e-15 || !amps.isFinite) return 0;
  final ratio = (amps.abs() / peakAmps).clamp(0.0, 1.0);
  if (ratio < 1e-4) return 0;
  return amps.sign * (0.35 + 2.9 * math.sqrt(ratio));
}

/// Spacing between charge dots, grid cells.
const double kChargeSpacing = 0.55;

/// Draws a schematic on the bench: grid, wires, parts, labels, and — while a
/// simulation runs — node voltage colours and moving charge.
class SchematicPainter extends CustomPainter {
  SchematicPainter({
    required this.doc,
    required this.view,
    this.selection = const {},
    this.frame,
    this.previewWire = const [],
    this.marquee,
    this.probeNode,
    this.probePart,
    this.flaggedIds = const {},
    this.showGrid = true,
    this.showLabels = true,
    this.opacity = 1,
    this.drawBackground = true,
    this.markOpenPins = true,
  });

  final SchematicDocument doc;
  final CanvasView view;
  final Set<String> selection;
  final RunFrame? frame;
  final List<(GridPoint, GridPoint)> previewWire;
  final Rect? marquee;
  final String? probeNode;
  final String? probePart;

  /// Parts drawn with a warning halo (shorted, invalid value).
  final Set<String> flaggedIds;
  final bool showGrid;
  final bool showLabels;
  final double opacity;
  final bool drawBackground;

  /// Rings on pins that touch nothing. Off for icons and thumbnails.
  final bool markOpenPins;

  double get s => view.scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (drawBackground) _background(canvas, size);
    if (showGrid) _grid(canvas, size);
    if (opacity < 1) {
      canvas.saveLayer(Offset.zero & size,
          Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    }
    _selectionHalos(canvas);
    _wires(canvas);
    for (final part in doc.parts) {
      _part(canvas, part);
    }
    _junctions(canvas);
    if (frame != null) _charge(canvas);
    if (showLabels && s >= 14) _labels(canvas);
    _probe(canvas);
    _preview(canvas);
    _marquee(canvas);
    if (opacity < 1) canvas.restore();
  }

  // ------------------------------------------------------------- background

  void _background(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Bench.backgroundTop, Bench.background],
        ).createShader(rect),
    );
  }

  void _grid(Canvas canvas, Size size) {
    final step = s < 16 ? 2 : 1;
    final topLeft = view.toGrid(Offset.zero);
    final bottomRight = view.toGrid(Offset(size.width, size.height));
    final x0 = (topLeft.dx.floor() ~/ step) * step - step;
    final y0 = (topLeft.dy.floor() ~/ step) * step - step;
    final x1 = bottomRight.dx.ceil() + step;
    final y1 = bottomRight.dy.ceil() + step;

    // Every fifth line, faintly: a sense of scale without graph paper.
    final major = Paint()
      ..color = Bench.gridMajor
      ..strokeWidth = 1;
    for (var x = (x0 ~/ 5) * 5; x <= x1; x += 5) {
      final sx = x * s + view.offset.dx;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), major);
    }
    for (var y = (y0 ~/ 5) * 5; y <= y1; y += 5) {
      final sy = y * s + view.offset.dy;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), major);
    }

    final dot = Paint()..color = Bench.gridDot;
    final r = (s * 0.045).clamp(0.8, 1.6);
    for (var x = x0; x <= x1; x += step) {
      for (var y = y0; y <= y1; y += step) {
        canvas.drawCircle(view.toScreenXY(x.toDouble(), y.toDouble()), r, dot);
      }
    }
  }

  // ----------------------------------------------------------------- colour

  Color _colorAt(GridPoint p) {
    final f = frame;
    if (f == null) return Bench.wireIdle;
    final node = f.run.nodeAt(p);
    if (node == null) return Bench.wireIdle;
    return Bench.forVoltage(
        f.run.nodeVoltage(node, f.sample), f.run.peakVolts);
  }

  Paint _stroke(Color color, {double width = 2}) => Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  double get _wireWidth => (s * 0.075).clamp(1.6, 3.4);

  // ------------------------------------------------------------------ wires

  void _wires(Canvas canvas) {
    final running = frame != null;
    for (final w in doc.wires) {
      final color = _colorAt(w.from);
      final a = view.toScreen(w.from);
      final b = view.toScreen(w.to);
      if (running) {
        // A soft glow under a live wire: the bench is lit by the circuit.
        canvas.drawLine(
          a,
          b,
          _stroke(color.withValues(alpha: 0.22), width: _wireWidth * 3.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      canvas.drawLine(a, b, _stroke(color, width: _wireWidth));
    }
  }

  void _selectionHalos(Canvas canvas) {
    final halo = _stroke(Bench.selection.withValues(alpha: 0.28),
        width: (s * 0.5).clamp(8.0, 26.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final warn = _stroke(Bench.warning.withValues(alpha: 0.3),
        width: (s * 0.55).clamp(9.0, 28.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    for (final w in doc.wires) {
      if (selection.contains(w.id)) {
        canvas.drawLine(view.toScreen(w.from), view.toScreen(w.to), halo);
      }
    }
    for (final p in doc.parts) {
      final pins = p.pins;
      final a = view.toScreen(pins.first);
      final b = p.kind == PartKind.ground
          ? view.toScreen(p.origin) + _rotated(Offset(0, s * 0.8), p.rotation)
          : view.toScreen(pins.last);
      if (flaggedIds.contains(p.id)) canvas.drawLine(a, b, warn);
      if (selection.contains(p.id)) canvas.drawLine(a, b, halo);
    }
  }

  Offset _rotated(Offset o, int rotation) => switch (rotation & 3) {
        1 => Offset(-o.dy, o.dx),
        2 => Offset(-o.dx, -o.dy),
        3 => Offset(o.dy, -o.dx),
        _ => o,
      };

  // ------------------------------------------------------------------ parts

  void _part(Canvas canvas, SchematicPart part) {
    final origin = view.toScreen(part.origin);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate((part.rotation & 3) * math.pi / 2);

    final ink = _stroke(Bench.ink, width: (s * 0.06).clamp(1.3, 2.8));
    final pins = part.pins;
    final leadA = _stroke(_colorAt(pins.first), width: _wireWidth);
    final leadB = _stroke(_colorAt(pins.last), width: _wireWidth);

    switch (part.kind) {
      case PartKind.resistor:
        _leads(canvas, leadA, leadB, 0.45, 1.55);
        final path = Path()..moveTo(0.45 * s, 0);
        const peaks = 6;
        for (var i = 0; i < peaks; i++) {
          final x = 0.45 + (i + 0.5) * (1.1 / peaks);
          path.lineTo(x * s, (i.isEven ? -0.2 : 0.2) * s);
        }
        path.lineTo(1.55 * s, 0);
        canvas.drawPath(path, ink);
      case PartKind.capacitor:
        _leads(canvas, leadA, leadB, 0.88, 1.12);
        canvas.drawLine(
            Offset(0.88 * s, -0.36 * s), Offset(0.88 * s, 0.36 * s), ink);
        canvas.drawLine(
            Offset(1.12 * s, -0.36 * s), Offset(1.12 * s, 0.36 * s), ink);
      case PartKind.inductor:
        _leads(canvas, leadA, leadB, 0.4, 1.6);
        final path = Path()..moveTo(0.4 * s, 0);
        const loops = 4;
        const w = 1.2 / loops;
        for (var i = 0; i < loops; i++) {
          final x0 = 0.4 + i * w;
          path.arcTo(
            Rect.fromLTWH(x0 * s, -w / 2 * s, w * s, w * s),
            math.pi,
            math.pi,
            false,
          );
        }
        canvas.drawPath(path, ink);
      case PartKind.diode:
        _leads(canvas, leadA, leadB, 0.7, 1.3);
        final tri = Path()
          ..moveTo(0.7 * s, -0.32 * s)
          ..lineTo(1.3 * s, 0)
          ..lineTo(0.7 * s, 0.32 * s)
          ..close();
        canvas.drawPath(
            tri, Paint()..color = Bench.ink.withValues(alpha: 0.12));
        canvas.drawPath(tri, ink);
        canvas.drawLine(
            Offset(1.3 * s, -0.32 * s), Offset(1.3 * s, 0.32 * s), ink);
      case PartKind.dcSource:
        _sourceBody(canvas, ink, leadA, leadB);
        final t = 0.1 * s;
        // "+" on the first pin's side, "−" on the second's.
        final plus = Offset(0.78 * s, 0);
        canvas.drawLine(plus - Offset(t, 0), plus + Offset(t, 0), ink);
        canvas.drawLine(plus - Offset(0, t), plus + Offset(0, t), ink);
        final minus = Offset(1.22 * s, 0);
        canvas.drawLine(minus - Offset(0, t), minus + Offset(0, t), ink);
      case PartKind.sineSource:
        _sourceBody(canvas, ink, leadA, leadB);
        final wave = Path();
        for (var i = 0; i <= 24; i++) {
          final u = i / 24;
          // Drawn across the circle, perpendicular to the leads, so it reads
          // as "~" when the source stands upright.
          final y = (u - 0.5) * 0.52 * s;
          final x = 1.0 * s + math.sin(u * 2 * math.pi) * 0.14 * s;
          i == 0 ? wave.moveTo(x, y) : wave.lineTo(x, y);
        }
        canvas.drawPath(wave, ink);
      case PartKind.currentSource:
        _sourceBody(canvas, ink, leadA, leadB);
        canvas.drawLine(Offset(0.75 * s, 0), Offset(1.25 * s, 0), ink);
        final head = Path()
          ..moveTo(1.28 * s, 0)
          ..lineTo(1.12 * s, -0.1 * s)
          ..lineTo(1.12 * s, 0.1 * s)
          ..close();
        canvas.drawPath(head, Paint()..color = Bench.ink);
      case PartKind.toggleSwitch:
        _leads(canvas, leadA, leadB, 0.6, 1.4);
        final contact = Paint()..color = Bench.ink;
        final r = (s * 0.07).clamp(1.6, 3.2);
        canvas.drawCircle(Offset(0.6 * s, 0), r, contact);
        canvas.drawCircle(Offset(1.4 * s, 0), r, contact);
        final angle = part.closed ? 0.0 : -0.5;
        final tip = Offset(0.6 * s + math.cos(angle) * 0.8 * s,
            math.sin(angle) * 0.8 * s);
        canvas.drawLine(Offset(0.6 * s, 0), tip,
            _stroke(part.closed ? Bench.ink : Bench.warning,
                width: ink.strokeWidth * 1.15));
      case PartKind.ground:
        canvas.drawLine(Offset.zero, Offset(0, 0.42 * s), leadA);
        for (var i = 0; i < 3; i++) {
          final half = (0.36 - i * 0.12) * s;
          final y = (0.42 + i * 0.13) * s;
          canvas.drawLine(Offset(-half, y), Offset(half, y), ink);
        }
    }
    canvas.restore();

    // Pin markers: open rings on pins that touch nothing, so a part that is
    // not wired in is obvious before anyone presses Run.
    for (final pin in pins) {
      if (markOpenPins && !_isConnected(pin, part)) {
        canvas.drawCircle(
          view.toScreen(pin),
          (s * 0.11).clamp(2.5, 5.0),
          _stroke(Bench.warning.withValues(alpha: 0.9), width: 1.5),
        );
      }
    }
  }

  void _leads(Canvas canvas, Paint a, Paint b, double from, double to) {
    canvas.drawLine(Offset.zero, Offset(from * s, 0), a);
    canvas.drawLine(Offset(to * s, 0), Offset(2 * s, 0), b);
  }

  void _sourceBody(Canvas canvas, Paint ink, Paint leadA, Paint leadB) {
    _leads(canvas, leadA, leadB, 0.55, 1.45);
    canvas.drawCircle(Offset(1.0 * s, 0), 0.45 * s,
        Paint()..color = Bench.ink.withValues(alpha: 0.06));
    canvas.drawCircle(Offset(1.0 * s, 0), 0.45 * s, ink);
  }

  late final Map<GridPoint, int> _touchCount = _countTouches();

  Map<GridPoint, int> _countTouches() {
    final count = <GridPoint, int>{};
    void add(GridPoint p, [int n = 1]) => count[p] = (count[p] ?? 0) + n;
    for (final w in doc.wires) {
      add(w.from);
      add(w.to);
    }
    for (final p in doc.parts) {
      for (final pin in p.pins) {
        add(pin);
      }
    }
    // A point in the middle of a wire counts as two touches (the wire goes
    // both ways from it).
    final points = count.keys.toList();
    for (final w in doc.wires) {
      for (final p in points) {
        if (p != w.from && p != w.to && w.contains(p)) add(p, 2);
      }
    }
    return count;
  }

  bool _isConnected(GridPoint pin, SchematicPart part) =>
      (_touchCount[pin] ?? 0) >= 2;

  void _junctions(Canvas canvas) {
    final r = (s * 0.12).clamp(2.6, 5.0);
    _touchCount.forEach((p, n) {
      if (n >= 3) {
        canvas.drawCircle(view.toScreen(p), r, Paint()..color = _colorAt(p));
      }
    });
  }

  // ----------------------------------------------------------------- charge

  void _charge(Canvas canvas) {
    final f = frame!;
    final peak = f.run.peakAmps;
    final dotR = (s * 0.085).clamp(1.8, 3.6);
    final glow = Paint()
      ..color = Bench.charge.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, dotR * 1.4);
    final core = Paint()..color = Bench.charge;

    void dots(Offset a, Offset b, double lengthCells, double current,
        String key) {
      if (lengthCells <= 0) return;
      if (chargeSpeed(current, peak) == 0) return;
      final travelled = f.chargeOffsets[key] ?? 0;
      final phase = travelled % kChargeSpacing;
      for (var d = phase; d < lengthCells; d += kChargeSpacing) {
        final p = Offset.lerp(a, b, d / lengthCells)!;
        canvas.drawCircle(p, dotR * 1.8, glow);
        canvas.drawCircle(p, dotR, core);
      }
    }

    final segments = f.flow.segments;
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      dots(view.toScreen(seg.a), view.toScreen(seg.b), seg.length,
          f.segmentCurrents[i], 's:$i');
    }
    for (final part in doc.parts) {
      if (part.kind == PartKind.ground) continue;
      final pins = part.pins;
      dots(view.toScreen(pins.first), view.toScreen(pins.last), 2,
          f.run.partCurrent(part.id, f.sample), 'p:${part.id}');
    }
  }

  // ----------------------------------------------------------------- labels

  static final Map<String, TextPainter> _textCache = {};

  TextPainter _text(String text, TextStyle style) {
    final key = '$text|${style.fontSize}|${style.color?.toARGB32()}|'
        '${style.fontWeight}';
    final cached = _textCache[key];
    if (cached != null) return cached;
    if (_textCache.length > 400) _textCache.clear();
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return _textCache[key] = painter;
  }

  void _labels(Canvas canvas) {
    final size = (s * 0.34).clamp(9.5, 14.0);
    // Labels are ids and SI values (Latin, µ, Ω). Naming Roboto keeps them
    // identical on Android and in rendered store screenshots; iOS falls
    // back to its system face.
    final idStyle = TextStyle(
        fontFamily: 'Roboto',
        fontSize: size * 0.86,
        color: Bench.inkDim,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4);
    final valueStyle = TextStyle(
        fontFamily: 'Roboto',
        fontSize: size,
        color: Bench.ink,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()]);

    for (final part in doc.parts) {
      if (part.kind == PartKind.ground) continue;
      final pins = part.pins;
      final a = view.toScreen(pins.first);
      final b = view.toScreen(pins.last);
      final mid = (a + b) / 2;
      final horizontal = (a.dy - b.dy).abs() < 1;
      final value = partValueLabel(part);
      final idText = _text(part.id, idStyle);
      final valueText =
          value.isEmpty ? null : _text(value, valueStyle);
      final gap = 0.62 * s;
      if (horizontal) {
        // Above the body, id then value on one line.
        final total = idText.width + (valueText == null ? 0 : 6 + valueText.width);
        var x = mid.dx - total / 2;
        final y = mid.dy - gap - math.max(idText.height, valueText?.height ?? 0);
        idText.paint(canvas, Offset(x, y + 1));
        if (valueText != null) {
          x += idText.width + 6;
          valueText.paint(canvas, Offset(x, y));
        }
      } else {
        // To the right, stacked.
        final x = mid.dx + gap;
        final h = idText.height + (valueText?.height ?? 0);
        idText.paint(canvas, Offset(x, mid.dy - h / 2));
        valueText?.paint(canvas, Offset(x, mid.dy - h / 2 + idText.height));
      }
    }
  }

  // ------------------------------------------------------------ probe/ghost

  void _probe(Canvas canvas) {
    final f = frame;
    if (f == null) return;
    if (probeNode != null) {
      // Mark the probed node where it is easiest to see: its first point.
      GridPoint? at;
      f.run.build.nodeOfPoint.forEach((p, n) {
        if (at == null && n == probeNode) at = p;
      });
      if (at != null) {
        final c = view.toScreen(at!);
        final r = (s * 0.3).clamp(7.0, 13.0);
        canvas.drawCircle(
            c,
            r * 1.6,
            Paint()
              ..color = Bench.positive.withValues(alpha: 0.18)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        canvas.drawCircle(c, r, _stroke(Bench.positive, width: 2));
        canvas.drawCircle(c, r * 0.35, Paint()..color = Bench.positive);
      }
    }
    if (probePart != null) {
      final part = doc.partById(probePart!);
      if (part != null && part.kind != PartKind.ground) {
        final pins = part.pins;
        final c = (view.toScreen(pins.first) + view.toScreen(pins.last)) / 2;
        canvas.drawCircle(
            c, 0.72 * s, _stroke(Bench.positive.withValues(alpha: 0.7), width: 1.6));
      }
    }
  }

  void _preview(Canvas canvas) {
    if (previewWire.isEmpty) return;
    final paint = _stroke(Bench.selection, width: _wireWidth);
    for (final (a, b) in previewWire) {
      canvas.drawLine(view.toScreen(a), view.toScreen(b), paint);
    }
    final end = view.toScreen(previewWire.last.$2);
    canvas.drawCircle(end, (s * 0.16).clamp(4.0, 7.0),
        Paint()..color = Bench.selection.withValues(alpha: 0.85));
  }

  void _marquee(Canvas canvas) {
    final m = marquee;
    if (m == null) return;
    final rect = Rect.fromPoints(view.toScreenXY(m.left, m.top),
        view.toScreenXY(m.right, m.bottom));
    canvas.drawRect(
        rect, Paint()..color = Bench.selection.withValues(alpha: 0.08));
    canvas.drawRect(rect, _stroke(Bench.selection.withValues(alpha: 0.7), width: 1));
  }

  @override
  bool shouldRepaint(covariant SchematicPainter old) => true;
}

/// A part's symbol drawn at icon size — used by the palette so the buttons
/// show exactly what lands on the canvas.
class PartGlyphPainter extends CustomPainter {
  PartGlyphPainter(this.kind);

  final PartKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final doc = SchematicDocument(parts: [
      SchematicPart(
        id: 'x',
        kind: kind,
        origin: const GridPoint(0, 0),
        closed: false,
      ),
    ]);
    final ground = kind == PartKind.ground;
    final scale = ground ? size.height / 0.9 : size.width / 2.1;
    final origin = ground
        ? Offset(size.width / 2, size.height * 0.1)
        : Offset((size.width - 2 * scale) / 2, size.height / 2);
    SchematicPainter(
      doc: doc,
      view: CanvasView(offset: origin, scale: scale),
      showGrid: false,
      showLabels: false,
      drawBackground: false,
      markOpenPins: false,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant PartGlyphPainter old) => old.kind != kind;
}
