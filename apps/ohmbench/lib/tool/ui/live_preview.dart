import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../schematic/document.dart';
import '../sim/flow.dart';
import '../sim/simulation.dart';
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
  });

  final SchematicDocument doc;
  final bool live;
  final bool showGrid;
  final bool showLabels;
  final double margin;
  final double maxScale;

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

  static const double _playSeconds = 5;

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
        !MediaQuery.of(context).disableAnimations &&
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
        : loopFrom + ((_playback % _playSeconds) / _playSeconds * span).round();
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
      final view = CanvasView.fit(widget.doc, constraints.biggest,
          margin: widget.margin, maxScale: widget.maxScale);
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
      return CustomPaint(
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
    });
  }
}
