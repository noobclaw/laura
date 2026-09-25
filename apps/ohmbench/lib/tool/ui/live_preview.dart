import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../schematic/document.dart';
import '../sim/flow.dart';
import '../sim/simulation.dart';
import 'lab_theme.dart';
import 'schematic_painter.dart';

/// A circuit drawn on the bench and, when [live], actually running: node
/// colours follow the simulated voltages and charge flows along the copper.
///
/// Used for the library's hero (the signature scene a new user sees first)
/// and, static, for project thumbnails. Respects the system's reduce-motion
/// setting by showing the settled state without movement.
class LivePreview extends StatefulWidget {
  const LivePreview({
    super.key,
    required this.doc,
    this.live = false,
    this.showGrid = true,
    this.showLabels = false,
    this.margin = 1.6,
    this.maxScale = 40,
    this.footer,
    this.footerHeight = 58,
    this.headerHeight = 0,
    this.overlay,
  });

  final SchematicDocument doc;
  final bool live;
  final bool showGrid;
  final bool showLabels;
  final double margin;
  final double maxScale;

  /// Drawn under the circuit from the same run and cursor, so a strip of
  /// scope trace can move in step with the charge above it.
  final Widget Function(SimRun run, int sample)? footer;

  /// Space kept free for [footer] under the framed circuit.
  final double footerHeight;

  /// Space kept free above the framed circuit (for an [overlay] title row).
  final double headerHeight;

  /// Laid over the whole preview from the same run and cursor — a live
  /// readout that ticks with the charge.
  final Widget Function(SimRun run, int sample)? overlay;

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview>
    with SingleTickerProviderStateMixin {
  SimRun? _run;
  FlowGraph? _flow;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _playback = 0;
  int _sample = 0;
  List<double> _segments = const [];
  final Map<String, double> _offsets = {};

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    if (widget.live) _simulate();
  }

  @override
  void didUpdateWidget(covariant LivePreview old) {
    super.didUpdateWidget(old);
    if (widget.live && !identical(old.doc, widget.doc)) _simulate();
  }

  void _simulate() {
    try {
      final run = simulateNow(widget.doc);
      if (!run.ok) return;
      _run = run;
      _flow = FlowGraph.build(widget.doc, run.build.nodeOfPoint);
      _sample = run.length - 1;
      _segments = _flow!.currents(widget.doc, (id) => run.partCurrent(id, _sample));
    } catch (e) {
      debugPrint('preview skipped: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = widget.live &&
        _run != null &&
        !BenchMotion.reduced(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final run = _run;
    if (run == null) return;
    final dt = _last == Duration.zero
        ? 0.0
        : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _playback += dt;
    final loopFrom = run.loopFrom ?? (run.length - 1);
    final span = run.length - 1 - loopFrom;
    final sample = span <= 0
        ? run.length - 1
        : loopFrom + ((_playback % BenchMotion.previewPlaySeconds) / BenchMotion.previewPlaySeconds * span).round();
    if (sample != _sample) {
      _sample = sample;
      _segments = _flow!.currents(widget.doc, (id) => run.partCurrent(id, sample));
    }
    for (final part in widget.doc.parts) {
      final key = 'p:${part.id}';
      _offsets[key] = (_offsets[key] ?? 0) +
          chargeSpeed(run.partCurrent(part.id, sample), run.peakAmps) * dt;
    }
    for (var i = 0; i < _segments.length; i++) {
      final key = 's:$i';
      _offsets[key] =
          (_offsets[key] ?? 0) + chargeSpeed(_segments[i], run.peakAmps) * dt;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // With a footer, frame the circuit in the space above it.
      final reserve = widget.footer == null ? 0.0 : widget.footerHeight;
      final area = Size(constraints.maxWidth,
          (constraints.maxHeight - reserve - widget.headerHeight)
              .clamp(1.0, double.infinity));
      final fitted = CanvasView.fit(widget.doc, area,
          margin: widget.margin, maxScale: widget.maxScale);
      final view = fitted.copyWith(
          offset: fitted.offset + Offset(0, widget.headerHeight));
      final run = _run;
      final frame = run == null || _flow == null
          ? null
          : RunFrame(
              run: run,
              sample: _sample,
              segmentCurrents: _segments,
              flow: _flow!,
              chargeOffsets: _offsets,
            );
      final painter = CustomPaint(
        size: constraints.biggest,
        painter: SchematicPainter(
          doc: widget.doc,
          view: view,
          frame: frame,
          showGrid: widget.showGrid,
          showLabels: widget.showLabels,
          markOpenPins: false,
        ),
      );
      final footer = widget.footer;
      final overlay = widget.overlay;
      if ((footer == null && overlay == null) || run == null) return painter;
      return Stack(children: [
        Positioned.fill(child: painter),
        if (footer != null)
          Positioned(left: 0, right: 0, bottom: 0, child: footer(run, _sample)),
        if (overlay != null) Positioned.fill(child: overlay(run, _sample)),
      ]);
    });
  }
}
