import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../bench/words.dart';
import '../../bench/rating_nudge.dart';
import '../engine/engine.dart';
import '../format.dart';
import '../pro.dart';
import '../schematic/document.dart';
import '../schematic/editing.dart';
import '../sim/flow.dart';
import '../sim/simulation.dart';
import '../store.dart';
import 'lab_theme.dart';
import 'part_sheet.dart';
import 'schematic_painter.dart';
import 'scope.dart';
import 'trouble.dart';

/// Real seconds a whole run takes to play back.
const double kPlaybackSeconds = 4;

enum _Gesture { none, pan, drag, wire, pinch }

/// The bench: one circuit, edited and simulated in place.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.store, required this.project});

  final ProjectStore store;
  final Project project;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with TickerProviderStateMixin {
  /// The circuit being edited. Starts as the widget's; becomes a saved
  /// project when a scratch example is saved as a copy.
  late Project _project = widget.project;

  late final EditHistory _history = EditHistory(widget.project.document);

  /// What is on screen. Equal to the history's document except during a
  /// drag, whose intermediate positions are not undo steps.
  late SchematicDocument _doc = widget.project.document;

  CanvasView? _view;
  Size _canvasSize = Size.zero;
  Set<String> _selection = {};

  // Gesture state.
  _Gesture _gesture = _Gesture.none;
  DragSession? _drag;
  SchematicDocument? _gestureStartDoc;
  GridPoint? _wireStart;
  GridPoint? _wireEnd;
  CanvasView? _pinchStartView;
  Offset? _pinchStartFocal;
  Offset? _marqueeStart;
  Rect? _marquee;
  bool _wireTool = false;

  /// Fingers currently down, counted with a raw [Listener]. Flutter's scale
  /// recognizer ends and restarts its gesture whenever a finger is added or
  /// lifted, so without this a second finger would first *commit* the drag
  /// it interrupts, and lifting one finger after a pinch would start a drag
  /// (or a wire) wherever the remaining finger rests (G8a audit P1-1).
  int _pointers = 0;

  /// True from the moment two fingers are down until every finger is up:
  /// nothing in such a touch sequence may edit the drawing.
  bool _pinchedThisSequence = false;

  // Simulation state.
  bool _running = false;
  bool _solving = false;
  SimRun? _run;
  FlowGraph? _flow;
  RunProblem? _problem;
  Set<SolverNote> _notes = {};
  int _generation = 0;
  double _playback = 0; // seconds into the current run's playback
  int _cachedSample = -1;
  List<double> _segmentCurrents = const [];
  final Map<String, double> _chargeOffsets = {};
  String? _probeNode;
  String? _probePart;
  bool _scopeOpen = true;
  Timer? _rerunTimer;
  // Created eagerly: a lazily created ticker would be instantiated inside
  // dispose() the first time an editor is closed without ever running,
  // which looks up an ancestor from a deactivated element and throws.
  late final Ticker _ticker;

  /// Short-lived "energy" rings where a part just landed or a wire just
  /// closed — feedback that the edit took, drawn over the canvas.
  final List<_Burst> _bursts = [];
  late final AnimationController _fx;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _fx = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 520))
      ..addListener(() {
        _bursts.removeWhere(
            (b) => DateTime.now().difference(b.born).inMilliseconds > 520);
        setState(() {});
      });
    widget.store.storageTrouble.addListener(_onStorage);
  }

  @override
  void dispose() {
    widget.store.storageTrouble.removeListener(_onStorage);
    _rerunTimer?.cancel();
    _ticker.dispose();
    _fx.dispose();
    widget.store.saveNow();
    super.dispose();
  }

  void _onStorage() {
    if (mounted) setState(() {});
  }

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  void _burst(Offset grid, Color color) {
    if (_reduceMotion) return;
    _bursts.add(_Burst(grid, color, DateTime.now()));
    _fx.forward(from: 0);
  }

  SchematicGeometry get _geometry =>
      SchematicGeometry(pixelsPerGrid: _view?.scale ?? 32);

  // ---------------------------------------------------------------- editing

  void _commit(SchematicDocument next, String label) {
    _history.push(next, label);
    setState(() {
      _doc = next;
      // The running result belongs to the previous drawing; stop drawing its
      // charge on wires that may have moved until the rerun lands.
      if (_running) _flow = null;
      _selection = _selection.where(_exists).toSet();
    });
    widget.store.updateDocument(_project, next);
    if (_running) _scheduleRerun();
  }

  bool _exists(String id) =>
      _doc.parts.any((p) => p.id == id) || _doc.wires.any((w) => w.id == id);

  void _undo() {
    if (!_history.canUndo) return;
    HapticFeedback.selectionClick();
    final doc = _history.undo();
    setState(() {
      _doc = doc;
      _selection = _selection.where(_exists).toSet();
      if (_running) _flow = null;
    });
    widget.store.updateDocument(_project, doc);
    if (_running) _scheduleRerun();
  }

  void _redo() {
    if (!_history.canRedo) return;
    HapticFeedback.selectionClick();
    final doc = _history.redo();
    setState(() {
      _doc = doc;
      _selection = _selection.where(_exists).toSet();
      if (_running) _flow = null;
    });
    widget.store.updateDocument(_project, doc);
    if (_running) _scheduleRerun();
  }

  Future<void> _addPart(PartKind kind) async {
    if (kind != PartKind.ground && widget.store.partLimitReached(_doc)) {
      await showProSheet(
        context,
        reason: tr(
          zh: '免费版每张电路图最多 ${ProjectStore.freeParts} 个元件(接地不算)。',
          en: 'The free version allows ${ProjectStore.freeParts} parts per circuit (ground is free).',
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    final origin = _freeSpotNearCentre(kind);
    final (next, part) = _doc.addPart(kind, origin);
    _commit(next, tr(zh: '添加 ${part.id}', en: 'Add ${part.id}'));
    setState(() => _selection = {part.id});
    final pins = part.pins;
    _burst(
        Offset((pins.first.x + pins.last.x) / 2, (pins.first.y + pins.last.y) / 2),
        Bench.positive);
  }

  /// The grid point nearest the middle of the screen where a new part does
  /// not land on anything that is already there.
  GridPoint _freeSpotNearCentre(PartKind kind) {
    final view = _view ?? const CanvasView();
    final c = view.toGrid(
      Offset(_canvasSize.width / 2, _canvasSize.height / 2),
    );
    final start = GridPoint(
      c.dx.round() - (kind == PartKind.ground ? 0 : 1),
      c.dy.round(),
    );
    final occupied = <GridPoint>{
      for (final p in _doc.parts) ...p.pins,
      for (final w in _doc.wires) ...[w.from, w.to],
    };
    bool free(GridPoint o) {
      final probe = SchematicPart(id: '_', kind: kind, origin: o);
      return probe.pins.every(
        (p) => !occupied.contains(p) && !_doc.wires.any((w) => w.contains(p)),
      );
    }

    for (var ring = 0; ring < 12; ring++) {
      for (var dy = -ring; dy <= ring; dy++) {
        for (var dx = -ring; dx <= ring; dx++) {
          if (dx.abs() != ring && dy.abs() != ring) continue;
          final o = start.translate(dx * 2, dy * 2);
          if (free(o)) return o;
        }
      }
    }
    return start;
  }

  void _rotateSelection() {
    final parts = _doc.parts.where((p) => _selection.contains(p.id)).toList();
    if (parts.isEmpty) return;
    var next = _doc;
    for (final p in parts) {
      next = next.replacePart(p.rotated());
    }
    _commit(next, tr(zh: '旋转', en: 'Rotate'));
  }

  void _deleteSelection() {
    if (_selection.isEmpty) return;
    HapticFeedback.mediumImpact();
    final count = _selection.length;
    final next = _doc.removeIds(_selection);
    setState(() => _selection = {});
    _commit(next, tr(zh: '删除 $count 项', en: 'Delete $count'));
  }

  Future<void> _editValue(SchematicPart part) async {
    final updated = await showPartValueSheet(context, part);
    if (updated == null || !mounted) return;
    final current = _doc.partById(part.id);
    if (current == null) return;
    _commit(
      _doc.replacePart(
        current.copyWith(
          value: updated.valueOverride,
          secondaryValue: updated.secondaryValue,
          resetValue: updated.valueOverride == null,
        ),
      ),
      tr(zh: '修改 ${part.id}', en: 'Edit ${part.id}'),
    );
  }

  void _flipSwitch(SchematicPart part) {
    HapticFeedback.mediumImpact();
    final flipped = part.copyWith(closed: !part.closed);
    final next = _doc.replacePart(flipped);
    _history.push(next, tr(zh: '拨动 ${part.id}', en: 'Flip ${part.id}'));
    setState(() => _doc = next);
    widget.store.updateDocument(_project, next);
    // A flip continues the running simulation from where it is, so a
    // capacitor charges from the voltage it had — that is the whole point
    // of a switch in a live circuit.
    if (_running) {
      _rerunTimer?.cancel();
      _continueRun();
    }
  }

  // --------------------------------------------------------------- gestures

  Offset _gridOf(Offset local) => _view!.toGrid(local);

  void _onTapUp(TapUpDetails d) {
    final g = _gridOf(d.localPosition);
    final hit = _geometry.hitTest(_doc, g.dx, g.dy);
    switch (hit) {
      case PartHit(:final part, :final pinIndex):
        if (part.kind == PartKind.toggleSwitch &&
            pinIndex == null &&
            (_running || _selection.contains(part.id))) {
          _flipSwitch(part);
          return;
        }
        if (_running) {
          HapticFeedback.selectionClick();
          setState(() {
            if (pinIndex != null) {
              _probeNode = _run?.nodeAt(part.pins[pinIndex]);
              _probePart = null;
            } else if (part.kind != PartKind.ground) {
              _probePart = part.id;
              _probeNode = null;
            }
            _scopeOpen = true;
          });
        }
        setState(() => _selection = {part.id});
      case WireHit(:final wire):
        if (_running) {
          HapticFeedback.selectionClick();
          setState(() {
            _probeNode = _run?.nodeAt(wire.from);
            _probePart = null;
            _scopeOpen = true;
          });
        }
        setState(() => _selection = {wire.id});
      case EmptyHit():
        setState(() => _selection = {});
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers >= 2 && !_pinchedThisSequence) {
      _pinchedThisSequence = true;
      // Put back whatever the first finger was doing, without an undo step.
      if (_gesture == _Gesture.drag && _gestureStartDoc != null) {
        _doc = _gestureStartDoc!;
      }
      setState(() {
        _gesture = _Gesture.none;
        _drag = null;
        _wireStart = null;
        _wireEnd = null;
        _gestureStartDoc = null;
      });
    }
  }

  void _onPointerGone(PointerEvent e) {
    _pointers = (_pointers - 1).clamp(0, 10);
    if (_pointers == 0) _pinchedThisSequence = false;
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (d.pointerCount >= 2) {
      _beginPinch(d.localFocalPoint);
      return;
    }
    if (_pinchedThisSequence) {
      // One finger left over from a pinch only pans.
      _gesture = _Gesture.pan;
      return;
    }
    final g = _gridOf(d.localFocalPoint);
    final hit = _geometry.hitTest(_doc, g.dx, g.dy);
    _gestureStartDoc = _doc;
    if (_wireTool) {
      _beginWire(
        hit is PartHit && hit.pinIndex != null
            ? hit.part.pins[hit.pinIndex!]
            : GridPoint(g.dx.round(), g.dy.round()),
      );
      return;
    }
    switch (hit) {
      case PartHit(:final part, :final pinIndex) when pinIndex != null:
        _beginWire(part.pins[pinIndex]);
      case PartHit(:final part):
        _beginDrag(part.id, g);
      case WireHit(:final wire):
        _beginDrag(wire.id, g);
      case EmptyHit():
        _gesture = _Gesture.pan;
    }
  }

  void _beginPinch(Offset focal) {
    // A second finger cancels whatever the first one started.
    if (_gesture == _Gesture.drag && _gestureStartDoc != null) {
      _doc = _gestureStartDoc!;
    }
    _wireStart = null;
    _wireEnd = null;
    _gesture = _Gesture.pinch;
    _pinchStartView = _view;
    _pinchStartFocal = focal;
    setState(() {});
  }

  void _beginWire(GridPoint start) {
    _gesture = _Gesture.wire;
    _wireStart = start;
    _wireEnd = start;
  }

  void _beginDrag(String id, Offset g) {
    final ids = _selection.contains(id) ? _selection : {id};
    _gesture = _Gesture.drag;
    _drag = DragSession(
      geometry: _geometry,
      startX: g.dx,
      startY: g.dy,
      ids: ids,
    );
    setState(() => _selection = ids);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2 && _gesture != _Gesture.pinch) {
      _beginPinch(d.localFocalPoint);
    }
    switch (_gesture) {
      case _Gesture.pinch:
        final start = _pinchStartView!;
        final scale = (start.scale * d.scale)
            .clamp(CanvasView.minScale, CanvasView.maxScale)
            .toDouble();
        // Keep the grid point that was under the fingers under the fingers.
        final anchor = start.toGrid(_pinchStartFocal!);
        setState(
          () => _view = CanvasView(
            scale: scale,
            offset: d.localFocalPoint - anchor * scale,
          ),
        );
      case _Gesture.pan:
        setState(
          () => _view = _view!.copyWith(
            offset: _view!.offset + d.focalPointDelta,
          ),
        );
      case _Gesture.drag:
        final g = _gridOf(d.localFocalPoint);
        final moved = _drag!.update(_doc, g.dx, g.dy);
        if (!identical(moved, _doc)) {
          HapticFeedback.selectionClick();
          setState(() => _doc = moved);
        }
      case _Gesture.wire:
        final g = _gridOf(d.localFocalPoint);
        final end = GridPoint(g.dx.round(), g.dy.round());
        if (end != _wireEnd) setState(() => _wireEnd = end);
      case _Gesture.none:
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    switch (_gesture) {
      case _Gesture.drag:
        final (dx, dy) = _drag!.applied;
        if (dx != 0 || dy != 0) {
          final count = _drag!.ids.length;
          _commit(_doc, tr(zh: '移动 $count 项', en: 'Move $count'));
        }
      case _Gesture.wire:
        final a = _wireStart!;
        final b = _wireEnd!;
        if (a != b) {
          var next = _doc;
          for (final (from, to) in _route(a, b)) {
            (next, _) = next.addWire(from, to);
          }
          HapticFeedback.lightImpact();
          _commit(next, tr(zh: '连线', en: 'Wire'));
          _burst(Offset(b.x.toDouble(), b.y.toDouble()), Bench.charge);
        }
      default:
    }
    setState(() {
      _gesture = _Gesture.none;
      _drag = null;
      _wireStart = null;
      _wireEnd = null;
      _gestureStartDoc = null;
    });
  }

  /// Wires go straight, or at 45 degrees, or as an L — horizontal first,
  /// which is how people draw schematics by hand.
  List<(GridPoint, GridPoint)> _route(GridPoint a, GridPoint b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    if (dx == 0 || dy == 0 || dx.abs() == dy.abs()) return [(a, b)];
    final corner = GridPoint(b.x, a.y);
    return [(a, corner), (corner, b)];
  }

  void _onLongPressStart(LongPressStartDetails d) {
    HapticFeedback.mediumImpact();
    final g = _gridOf(d.localPosition);
    final hit = _geometry.hitTest(_doc, g.dx, g.dy);
    if (hit is! EmptyHit) {
      // Long-press on something: select it and offer its actions.
      final id = switch (hit) {
        PartHit(:final part) => part.id,
        WireHit(:final wire) => wire.id,
        _ => null,
      };
      if (id != null) setState(() => _selection = {..._selection, id});
      return;
    }
    setState(() {
      _marqueeStart = g;
      _marquee = Rect.fromPoints(g, g);
    });
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (_marqueeStart == null) {
      // Hold-then-drag on a part moves the selection.
      final g = _gridOf(d.localPosition);
      if (_gesture != _Gesture.drag && _selection.isNotEmpty) {
        _gestureStartDoc = _doc;
        _gesture = _Gesture.drag;
        final start = _gridOf(d.localPosition - d.localOffsetFromOrigin);
        _drag = DragSession(
          geometry: _geometry,
          startX: start.dx,
          startY: start.dy,
          ids: _selection,
        );
      }
      if (_gesture == _Gesture.drag && _drag != null) {
        final moved = _drag!.update(_doc, g.dx, g.dy);
        if (!identical(moved, _doc)) setState(() => _doc = moved);
      }
      return;
    }
    setState(
      () =>
          _marquee = Rect.fromPoints(_marqueeStart!, _gridOf(d.localPosition)),
    );
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    final m = _marquee;
    if (m == null) {
      if (_gesture == _Gesture.drag && _drag != null) {
        final (dx, dy) = _drag!.applied;
        if (dx != 0 || dy != 0) {
          _commit(
            _doc,
            tr(
              zh: '移动 ${_drag!.ids.length} 项',
              en: 'Move ${_drag!.ids.length}',
            ),
          );
        }
      }
      setState(() {
        _gesture = _Gesture.none;
        _drag = null;
        _gestureStartDoc = null;
      });
      return;
    }
    final ids = _geometry.idsInRect(_doc, m.left, m.top, m.right, m.bottom);
    setState(() {
      _selection = ids;
      _marquee = null;
      _marqueeStart = null;
    });
  }

  void _fit() => setState(() => _view = _fitView(_canvasSize));

  /// Frames the drawing above the run button and status line, which sit
  /// over the bottom of the canvas.
  CanvasView _fitView(Size size) {
    const reserve = 96.0;
    final usable = Size(
      size.width,
      (size.height - reserve).clamp(1, double.infinity),
    );
    return CanvasView.fit(_doc, usable, margin: 1.6, maxScale: 56);
  }

  // ------------------------------------------------------------- simulation

  Future<void> _toggleRun() async {
    HapticFeedback.mediumImpact();
    if (_running) {
      _stop();
      return;
    }
    setState(() {
      _running = true;
      _scopeOpen = true;
    });
    // Only a run the user asked for counts toward the review prompt's
    // "third completed simulation", not the reruns that follow edits.
    if (await _startRun()) RatingNudge.noteCoreAction();
  }

  void _stop() {
    _generation++;
    _rerunTimer?.cancel();
    _ticker.stop();
    setState(() {
      _running = false;
      _solving = false;
      _run = null;
      _flow = null;
      _problem = null;
      _notes = {};
    });
  }

  void _scheduleRerun() {
    _rerunTimer?.cancel();
    _rerunTimer = Timer(const Duration(milliseconds: 280), () {
      if (mounted && _running) _startRun();
    });
  }

  Future<bool> _startRun() {
    final doc = _doc;
    return _launch(doc, simulate(doc));
  }

  /// Continues from the state at the playback cursor: a switch flip.
  Future<bool> _continueRun() {
    final run = _run;
    if (run == null || !run.ok) return _startRun();
    final i = _sampleIndex(run);
    final (volts, amps) = run.stateAt(_doc, i);
    final doc = _doc;
    return _launch(
      doc,
      simulate(
        doc,
        initialVolts: volts,
        initialAmps: amps,
        timeOffset: run.timeOffset + run.times[i],
      ),
    );
  }

  /// Shows the result of [pending] unless a newer run has started since.
  /// Returns true when a playable run arrived.
  Future<bool> _launch(
    SchematicDocument simulated,
    Future<SimRun> pending,
  ) async {
    final generation = ++_generation;
    setState(() => _solving = true);
    final SimRun result;
    try {
      result = await pending;
    } catch (e) {
      debugPrint('simulation failed: $e');
      if (!mounted || generation != _generation) return false;
      setState(() {
        _solving = false;
        _problem = RunProblem.failed;
        _notes = {SolverNote.didNotConverge};
      });
      return false;
    }
    if (!mounted || generation != _generation || !_running) return false;
    setState(() {
      _solving = false;
      _problem = result.problem;
      _notes = result.notes;
      if (!result.ok) {
        _run = null;
        _flow = null;
        _ticker.stop();
        return;
      }
      _run = result;
      // Built from the drawing that was simulated, whose node map this is.
      // If the user edited meanwhile, a rerun is already scheduled.
      _flow = identical(simulated, _doc)
          ? FlowGraph.build(simulated, result.build.nodeOfPoint)
          : null;
      _cachedSample = -1;
      _playback = 0;
      _chargeOffsets.clear();
      _pickDefaultProbe(result);
    });
    if (result.ok) {
      _lastTick = Duration.zero;
      if (!_ticker.isActive) _ticker.start();
    }
    return result.ok;
  }

  /// A useful first thing to watch: a capacitor's voltage, else an
  /// inductor's current, else the node a diode feeds, else a source.
  void _pickDefaultProbe(SimRun run) {
    final probedNodeExists =
        _probeNode != null && run.nodeSeries.containsKey(_probeNode);
    final probedPartExists =
        _probePart != null && run.partSeries.containsKey(_probePart);
    if (probedNodeExists || probedPartExists) return;
    _probeNode = null;
    _probePart = null;
    SchematicPart? pick(PartKind k) {
      for (final p in _doc.parts) {
        if (p.kind == k && !run.build.invalidPartIds.contains(p.id)) return p;
      }
      return null;
    }

    final cap = pick(PartKind.capacitor);
    if (cap != null) {
      _probeNode = _nonGround(run, cap.pins);
      if (_probeNode != null) return;
    }
    final ind = pick(PartKind.inductor);
    if (ind != null) {
      _probePart = ind.id;
      return;
    }
    final diode = pick(PartKind.diode);
    if (diode != null) {
      _probeNode = _nonGround(run, diode.pins.reversed.toList());
      if (_probeNode != null) return;
    }
    for (final p in _doc.parts) {
      if (p.kind == PartKind.resistor) {
        _probeNode = _nonGround(run, p.pins.reversed.toList());
        if (_probeNode != null) return;
      }
    }
    for (final p in _doc.parts) {
      if (p.kind == PartKind.ground) continue;
      _probeNode = _nonGround(run, p.pins);
      if (_probeNode != null) return;
    }
  }

  String? _nonGround(SimRun run, List<GridPoint> pins) {
    for (final pin in pins) {
      final n = run.nodeAt(pin);
      if (n != null && n != kGroundNode) return n;
    }
    return null;
  }

  int _sampleIndex(SimRun run) {
    if (run.length <= 1) return 0;
    final loopFrom = run.loopFrom;
    final progress = _playback / kPlaybackSeconds;
    if (_reduceMotion) return run.length - 1;
    if (loopFrom == null) {
      return (progress.clamp(0.0, 1.0) * (run.length - 1)).round();
    }
    // First pass plays everything; after that, loop the settled part.
    if (progress <= 1) return (progress * (run.length - 1)).round();
    final loopLength = run.length - 1 - loopFrom;
    final loopSeconds = kPlaybackSeconds * loopLength / (run.length - 1);
    final into = (_playback - kPlaybackSeconds) % loopSeconds;
    return loopFrom + (into / loopSeconds * loopLength).round();
  }

  void _onTick(Duration elapsed) {
    final run = _run;
    if (run == null || !mounted) return;
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _playback += dt.clamp(0.0, 0.1);
    final i = _sampleIndex(run);
    if (i != _cachedSample) {
      _cachedSample = i;
      _segmentCurrents =
          _flow?.currents(_doc, (id) => run.partCurrent(id, i)) ?? const [];
    }
    if (!_reduceMotion) {
      // Charge moves in real time at a speed set by the current, not by the
      // slow-motion factor, so dots stay legible at any time scale.
      for (final part in _doc.parts) {
        final key = 'p:${part.id}';
        _chargeOffsets[key] =
            (_chargeOffsets[key] ?? 0) +
            chargeSpeed(run.partCurrent(part.id, i), run.peakAmps) * dt;
      }
      for (var s = 0; s < _segmentCurrents.length; s++) {
        final key = 's:$s';
        _chargeOffsets[key] =
            (_chargeOffsets[key] ?? 0) +
            chargeSpeed(_segmentCurrents[s], run.peakAmps) * dt;
      }
    }
    setState(() {});
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final run = _run;
    final sample = run == null ? 0 : _sampleIndex(run);
    final build = run?.build ?? _doc.buildNetlist();
    final flagged = {...build.shortedPartIds, ...build.invalidPartIds};

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Bench.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(
                name: _project.name,
                scratch: _project.scratch,
                onSaveCopy: _saveCopy,
                canUndo: _history.canUndo,
                canRedo: _history.canRedo,
                undoLabel: _history.undoLabel,
                redoLabel: _history.redoLabel,
                wireTool: _wireTool,
                onBack: () => Navigator.of(context).maybePop(),
                onRename: _rename,
                onUndo: _undo,
                onRedo: _redo,
                onWireTool: () => setState(() => _wireTool = !_wireTool),
                onFit: _fit,
                onHelp: _showHelp,
              ),
              if (widget.store.storageTrouble.value != null ||
                  widget.store.savingBlocked)
                _StorageBanner(
                  text: storageTroubleText(
                    widget.store.storageTrouble.value,
                    blocked: widget.store.savingBlocked,
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    if (_view == null || _canvasSize != size) {
                      final first = _view == null;
                      _canvasSize = size;
                      if (first) {
                        _view = _doc.isEmpty
                            ? CanvasView(
                                offset: Offset(size.width / 2, size.height / 2),
                              )
                            : _fitView(size);
                      }
                    }
                    return Stack(
                      children: [
                        Positioned.fill(child: _canvas(run, sample, flagged)),
                      if (_bursts.isNotEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _BurstPainter(_bursts, _view!),
                            ),
                          ),
                        ),
                        if (_doc.isEmpty) const _EmptyBench(),
                        Positioned(
                          left: 12,
                          right: 84,
                          bottom: 12,
                          child: _StatusArea(
                            problem: _problem,
                            notes: _notes,
                            netlistBuild: build,
                            doc: _doc,
                            running: _running,
                            solving: _solving,
                            run: run,
                            selection: _selection,
                            onRotate: _rotateSelection,
                            onDelete: _deleteSelection,
                            onEdit: _editValue,
                            onFlip: _flipSwitch,
                          ),
                        ),
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: _RunButton(
                            running: _running,
                            solving: _solving,
                            onPressed: _toggleRun,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child:
                    _scopeFor(run, sample) ??
                    const SizedBox(width: double.infinity),
              ),
              _Palette(
                onPick: _addPart,
                atLimit: widget.store.partLimitReached(_doc),
                count: countedParts(_doc),
                pro: widget.store.pro,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _canvas(SimRun? run, int sample, Set<String> flagged) {
    final view = _view!;
    final frame = run == null || _flow == null
        ? null
        : RunFrame(
            run: run,
            sample: sample,
            segmentCurrents: _segmentCurrents.length == _flow!.segments.length
                ? _segmentCurrents
                : List<double>.filled(_flow!.segments.length, 0),
            flow: _flow!,
            chargeOffsets: _chargeOffsets,
          );
    final preview =
        _wireStart != null && _wireEnd != null && _wireStart != _wireEnd
        ? _route(_wireStart!, _wireEnd!)
        : const <(GridPoint, GridPoint)>[];
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerGone,
      onPointerCancel: _onPointerGone,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Hit-test where the finger went down, not where the drag was
        // recognised 18 px later — otherwise grabbing a pin would miss it.
        dragStartBehavior: DragStartBehavior.down,
        onTapUp: _onTapUp,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMove,
        onLongPressEnd: _onLongPressEnd,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: SchematicPainter(
              doc: _doc,
              view: view,
              selection: _selection,
              frame: frame,
              previewWire: preview,
              marquee: _marquee,
              probeNode: _probeNode,
              probePart: _probePart,
              flaggedIds: flagged,
            ),
          ),
        ),
      ),
    );
  }

  Widget? _scopeFor(SimRun? run, int sample) {
    if (!_running || run == null || !_scopeOpen) return null;
    final String title;
    final List<double> values;
    final String unit;
    if (_probePart != null && run.partSeries.containsKey(_probePart)) {
      title = tr(zh: '$_probePart 的电流', en: 'Current through $_probePart');
      values = run.partSeries[_probePart]!;
      unit = 'A';
    } else if (_probeNode != null) {
      title = _probeNode == kGroundNode
          ? tr(zh: '接地(参考点,恒为 0 V)', en: 'Ground (the reference, always 0 V)')
          : tr(zh: '节点电压(对地)', en: 'Node voltage (to ground)');
      values = run.nodeSeries[_probeNode] ?? _zeros(run.length);
      unit = 'V';
    } else {
      return null;
    }
    final slowdown = run.window <= 0 ? 1.0 : kPlaybackSeconds / run.window;
    return ScopePanel(
      key: const ValueKey('scope'),
      title: title,
      trace: _traceCache(values, run.window, unit),
      cursor: sample,
      cursorTime: run.timeOffset + (run.times.isEmpty ? 0 : run.times[sample]),
      slowdown: slowdown,
      hint: tr(
        zh: '点导线看电压,点元件看电流',
        en: 'Tap a wire for its voltage, a part for its current',
      ),
      onClose: () => setState(() => _scopeOpen = false),
    );
  }

  ScopeTrace? _trace;
  List<double>? _groundSeries;

  /// A flat 0 V trace for probing ground, reused so the scope does not
  /// replay its fade-in every frame.
  List<double> _zeros(int n) {
    final g = _groundSeries;
    if (g != null && g.length == n) return g;
    return _groundSeries = List<double>.filled(n, 0);
  }

  /// One trace object per series, so the scope's fade-in plays once per run
  /// instead of on every frame.
  ScopeTrace _traceCache(List<double> values, double window, String unit) {
    final t = _trace;
    if (t != null && identical(t.values, values) && t.unit == unit) return t;
    return _trace = ScopeTrace(values: values, window: window, unit: unit);
  }

  Future<void> _rename() async {
    if (_project.scratch) return _saveCopy();
    final name = await showRenameDialog(context, _project.name);
    if (name == null || !mounted) return;
    widget.store.rename(_project, name);
    setState(() {});
  }

  /// Turns a scratch example into one of the user's saved circuits.
  Future<void> _saveCopy() async {
    if (!_project.scratch) return;
    if (widget.store.atProjectLimit) {
      await showProSheet(
        context,
        reason: tr(
          zh: '免费版保存 ${ProjectStore.freeProjects} 张电路图,你已经有了。示例可以随便运行和修改,只是不能再存一份。',
          en: 'The free version keeps ${ProjectStore.freeProjects} circuit and you already have one. Examples still run and edit freely; they just cannot be saved as another.',
        ),
      );
      return;
    }
    final saved = widget.store.create(_project.name, _doc);
    HapticFeedback.mediumImpact();
    setState(() => _project = saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(
          zh: '已存为「${saved.name}」,之后的每一步都会自动保存',
          en: 'Saved as "${saved.name}". Every step from now on saves itself.')),
    ));
  }

  void _showHelp() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => const _HelpSheet(),
    );
  }
}

/// Asks for a circuit name. Returns null when cancelled or left blank.
Future<String?> showRenameDialog(BuildContext context, String current) {
  final controller = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(zh: '重命名', en: 'Rename')),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: tr(zh: '电路名称', en: 'Circuit name'),
        ),
        onSubmitted: (v) =>
            Navigator.of(ctx).pop(v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(tr(zh: '取消', en: 'Cancel')),
        ),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            Navigator.of(ctx).pop(v.isEmpty ? null : v);
          },
          child: Text(tr(zh: '保存', en: 'Save')),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

// ------------------------------------------------------------------ widgets

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.name,
    required this.scratch,
    required this.onSaveCopy,
    required this.canUndo,
    required this.canRedo,
    required this.undoLabel,
    required this.redoLabel,
    required this.wireTool,
    required this.onBack,
    required this.onRename,
    required this.onUndo,
    required this.onRedo,
    required this.onWireTool,
    required this.onFit,
    required this.onHelp,
  });

  final String name;
  final bool scratch;
  final VoidCallback onSaveCopy;
  final bool canUndo;
  final bool canRedo;
  final String? undoLabel;
  final String? redoLabel;
  final bool wireTool;
  final VoidCallback onBack;
  final VoidCallback onRename;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onWireTool;
  final VoidCallback onFit;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: Bench.backgroundTop,
        border: Border(bottom: BorderSide(color: Bench.panelBorder)),
      ),
      child: IconTheme(
        data: const IconThemeData(color: Bench.ink),
        child: Row(
          children: [
            IconButton(
              tooltip: tr(zh: '返回', en: 'Back'),
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onBack,
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onRename,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Bench.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (scratch)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Bench.charge.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(tr(zh: '示例', en: 'Example'),
                              style: const TextStyle(
                                  color: Bench.charge,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        )
                      else
                        const Icon(
                          Icons.edit_outlined,
                          size: 15,
                          color: Bench.inkDim,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (scratch)
              IconButton(
                tooltip: tr(zh: '存为我的电路', en: 'Save as my circuit'),
                icon: const Icon(Icons.bookmark_add_outlined, color: Bench.charge),
                onPressed: onSaveCopy,
              ),
            IconButton(
              tooltip: undoLabel == null
                  ? tr(zh: '撤销', en: 'Undo')
                  : tr(zh: '撤销:$undoLabel', en: 'Undo: $undoLabel'),
              icon: const Icon(Icons.undo_rounded),
              color: Bench.ink,
              disabledColor: Bench.inkDim.withValues(alpha: 0.35),
              onPressed: canUndo ? onUndo : null,
            ),
            IconButton(
              tooltip: redoLabel == null
                  ? tr(zh: '重做', en: 'Redo')
                  : tr(zh: '重做:$redoLabel', en: 'Redo: $redoLabel'),
              icon: const Icon(Icons.redo_rounded),
              color: Bench.ink,
              disabledColor: Bench.inkDim.withValues(alpha: 0.35),
              onPressed: canRedo ? onRedo : null,
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: wireTool
                    ? Bench.selection.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                tooltip: wireTool
                    ? tr(
                        zh: '连线模式:在画布任意处拖动画线',
                        en: 'Wire mode: drag anywhere to draw',
                      )
                    : tr(zh: '连线模式', en: 'Wire mode'),
                icon: Icon(
                  Icons.cable_rounded,
                  color: wireTool ? Bench.selection : Bench.ink,
                ),
                onPressed: onWireTool,
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Bench.ink),
              onSelected: (v) => v == 'fit' ? onFit() : onHelp(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'fit',
                  child: Text(tr(zh: '适配屏幕', en: 'Fit to screen')),
                ),
                PopupMenuItem(
                  value: 'help',
                  child: Text(tr(zh: '手势说明', en: 'Gestures')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageBanner extends StatelessWidget {
  const _StorageBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Bench.error.withValues(alpha: 0.16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(color: Bench.ink, fontSize: 13, height: 1.35),
      ),
    );
  }
}

class _EmptyBench extends StatelessWidget {
  const _EmptyBench();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 40,
                color: Bench.positive.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 14),
              Text(
                tr(zh: '从下方选一个元件开始', en: 'Pick a part below to start'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Bench.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  zh: '元件会出现在屏幕中央。从引脚拖出去就是连线,别忘了放一个接地。',
                  en: 'It lands in the middle of the screen. Drag from a pin to wire it, and remember a ground.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Bench.inkDim,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selection actions and the one line of status: what is wrong, or what is
/// being shown.
class _StatusArea extends StatelessWidget {
  const _StatusArea({
    required this.problem,
    required this.notes,
    required this.netlistBuild,
    required this.doc,
    required this.running,
    required this.solving,
    required this.run,
    required this.selection,
    required this.onRotate,
    required this.onDelete,
    required this.onEdit,
    required this.onFlip,
  });

  final RunProblem? problem;
  final Set<SolverNote> notes;
  final NetlistBuild netlistBuild;
  final SchematicDocument doc;
  final bool running;
  final bool solving;
  final SimRun? run;
  final Set<String> selection;
  final VoidCallback onRotate;
  final VoidCallback onDelete;
  final ValueChanged<SchematicPart> onEdit;
  final ValueChanged<SchematicPart> onFlip;

  (String, Color)? _message() {
    if (running) {
      switch (problem) {
        case RunProblem.empty:
          return (
            tr(
              zh: '画布是空的 —— 先放几个元件',
              en: 'The bench is empty — add some parts',
            ),
            Bench.warning,
          );
        case RunProblem.noGround:
          return (
            tr(
              zh: '缺少接地 —— 放一个 ⏚,电压才有参考点',
              en: 'No ground — add ⏚ so voltages have a reference',
            ),
            Bench.warning,
          );
        case RunProblem.invalidValues:
          return (
            tr(
              zh: '${netlistBuild.invalidPartIds.join('、')} 的数值无法仿真(必须大于 0)',
              en: '${netlistBuild.invalidPartIds.join(', ')}: value must be greater than zero',
            ),
            Bench.error,
          );
        case RunProblem.failed:
          if (notes.contains(SolverNote.singular)) {
            return (
              tr(
                zh: '短路:某个电压源被导线直接短接,或两个电源互相顶牛。没有显示任何数值。',
                en: 'Short circuit: a source is shorted by a wire, or two sources fight. No numbers shown.',
              ),
              Bench.error,
            );
          }
          return (
            tr(
              zh: '未收敛 —— 这个电路没有可信的解,所以一个数都不显示',
              en: 'Did not converge — no trustworthy answer, so no numbers are shown',
            ),
            Bench.error,
          );
        case null:
      }
      if (run != null && !run!.completed) {
        return (
          tr(
            zh: '在 ${formatSi(run!.window, 's')} 处未收敛,之后的波形不显示',
            en: 'Stopped converging at ${formatSi(run!.window, 's')}; nothing after it is shown',
          ),
          Bench.error,
        );
      }
      if (notes.contains(SolverNote.floatingNodesTiedToGround)) {
        return (
          tr(
            zh: '有元件悬空(没接到电路里),它上面的读数没有意义',
            en: 'Something is floating (not connected); its readings mean nothing',
          ),
          Bench.warning,
        );
      }
    }
    if (netlistBuild.shortedPartIds.isNotEmpty) {
      return (
        tr(
          zh: '${netlistBuild.shortedPartIds.join('、')} 被短接:两个引脚落在同一根导线上',
          en: '${netlistBuild.shortedPartIds.join(', ')} is shorted: both pins touch the same wire',
        ),
        Bench.warning,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final message = _message();
    final selected = doc.parts.where((p) => selection.contains(p.id)).toList();
    final wires = doc.wires.where((w) => selection.contains(w.id)).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.25),
                end: Offset.zero,
              ).animate(a),
              child: child,
            ),
          ),
          child: selection.isEmpty
              ? const SizedBox.shrink()
              : _SelectionBar(
                  key: ValueKey(selection.join(',')),
                  parts: selected,
                  wireCount: wires,
                  onRotate: onRotate,
                  onDelete: onDelete,
                  onEdit: onEdit,
                  onFlip: onFlip,
                ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: message == null
              ? const SizedBox.shrink()
              : Container(
                  key: ValueKey(message.$1),
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Bench.panel.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: message.$2.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: message.$2,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          message.$1,
                          style: const TextStyle(
                            color: Bench.ink,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    super.key,
    required this.parts,
    required this.wireCount,
    required this.onRotate,
    required this.onDelete,
    required this.onEdit,
    required this.onFlip,
  });

  final List<SchematicPart> parts;
  final int wireCount;
  final VoidCallback onRotate;
  final VoidCallback onDelete;
  final ValueChanged<SchematicPart> onEdit;
  final ValueChanged<SchematicPart> onFlip;

  @override
  Widget build(BuildContext context) {
    final single = parts.length == 1 && wireCount == 0 ? parts.first : null;
    final String label;
    if (single != null) {
      final value = partValueLabel(single);
      label = value.isEmpty ? single.id : '${single.id} · $value';
    } else if (parts.isEmpty && wireCount == 1) {
      label = tr(zh: '导线', en: 'Wire');
    } else {
      label = tr(
        zh: '已选 ${parts.length + wireCount} 项',
        en: '${parts.length + wireCount} selected',
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: Bench.panel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Bench.selection.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Bench.ink,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (single != null && hasEditableValue(single.kind))
            _BarButton(
              icon: Icons.tune_rounded,
              tooltip: tr(zh: '改数值', en: 'Edit value'),
              onTap: () => onEdit(single),
            ),
          if (single != null && single.kind == PartKind.toggleSwitch)
            _BarButton(
              icon: single.closed
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_rounded,
              tooltip: single.closed
                  ? tr(zh: '断开', en: 'Open')
                  : tr(zh: '闭合', en: 'Close'),
              onTap: () => onFlip(single),
            ),
          if (parts.isNotEmpty)
            _BarButton(
              icon: Icons.rotate_90_degrees_cw_outlined,
              tooltip: tr(zh: '旋转', en: 'Rotate'),
              onTap: onRotate,
            ),
          _BarButton(
            icon: Icons.delete_outline_rounded,
            tooltip: tr(zh: '删除', en: 'Delete'),
            color: Bench.error,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = Bench.ink,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: Icon(icon, color: color),
    onPressed: onTap,
  );
}

/// Run / stop. A ring breathes around it while the circuit is live.
class _RunButton extends StatefulWidget {
  const _RunButton({
    required this.running,
    required this.solving,
    required this.onPressed,
  });

  final bool running;
  final bool solving;
  final VoidCallback onPressed;

  @override
  State<_RunButton> createState() => _RunButtonState();
}

class _RunButtonState extends State<_RunButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant _RunButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    final animate = widget.running && !MediaQuery.of(context).disableAnimations;
    if (animate && !_pulse.isAnimating) _pulse.repeat();
    if (!animate && _pulse.isAnimating) _pulse.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.running;
    return Semantics(
      button: true,
      label: running
          ? tr(zh: '停止仿真', en: 'Stop simulation')
          : tr(zh: '运行仿真', en: 'Run simulation'),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1,
          duration: const Duration(milliseconds: 120),
          child: SizedBox(
            width: 64,
            height: 64,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => CustomPaint(
                painter: _PulsePainter(running ? _pulse.value : null),
                child: child,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: running
                        ? const [Color(0xFFFF7A7A), Color(0xFFE0435F)]
                        : const [Color(0xFFFFE27A), Color(0xFFE0AE1E)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (running ? Bench.error : Bench.charge).withValues(
                        alpha: 0.45,
                      ),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: widget.solving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (c, a) =>
                              ScaleTransition(scale: a, child: c),
                          child: Icon(
                            running
                                ? Icons.stop_rounded
                                : Icons.play_arrow_rounded,
                            key: ValueKey(running),
                            color: running
                                ? Colors.white
                                : const Color(0xFF2B2100),
                            size: 34,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t);

  final double? t;

  @override
  void paint(Canvas canvas, Size size) {
    final t = this.t;
    if (t == null) return;
    final c = size.center(Offset.zero);
    for (final phase in const [0.0, 0.5]) {
      final u = (t + phase) % 1;
      canvas.drawCircle(
        c,
        size.width / 2 + u * 18,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Bench.error.withValues(alpha: (1 - u) * 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) => old.t != t;
}

class _Palette extends StatelessWidget {
  const _Palette({
    required this.onPick,
    required this.atLimit,
    required this.count,
    required this.pro,
  });

  final ValueChanged<PartKind> onPick;
  final bool atLimit;
  final int count;
  final bool pro;

  static const _order = [
    PartKind.resistor,
    PartKind.capacitor,
    PartKind.inductor,
    PartKind.diode,
    PartKind.dcSource,
    PartKind.sineSource,
    PartKind.currentSource,
    PartKind.toggleSwitch,
    PartKind.ground,
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Bench.backgroundTop,
        border: Border(top: BorderSide(color: Bench.panelBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!pro)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr(
                  zh: '元件 $count / ${ProjectStore.freeParts}',
                  en: 'Parts $count / ${ProjectStore.freeParts}',
                ),
                style: TextStyle(
                  color: atLimit ? Bench.warning : Bench.inkDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              itemCount: _order.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final kind = _order[i];
                return _PaletteItem(kind: kind, onTap: () => onPick(kind));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteItem extends StatelessWidget {
  const _PaletteItem({required this.kind, required this.onTap});

  final PartKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: partKindName(kind),
      child: Material(
        color: Bench.panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          splashColor: Bench.positive.withValues(alpha: 0.2),
          onTap: onTap,
          child: Container(
            width: 70,
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Bench.panelBorder),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 44,
                  height: 26,
                  child: CustomPaint(painter: PartGlyphPainter(kind)),
                ),
                const Spacer(),
                Text(
                  partKindShort(kind),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(
                    color: Bench.inkDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = <(IconData, String)>[
      (
        Icons.add_circle_outline,
        tr(zh: '点下方元件:放到屏幕中央', en: 'Tap a part below: it lands mid-screen'),
      ),
      (
        Icons.open_with_rounded,
        tr(
          zh: '拖元件或导线:移动(贴合栅格)',
          en: 'Drag a part or wire: move it (snaps to grid)',
        ),
      ),
      (
        Icons.polyline_rounded,
        tr(
          zh: '从引脚拖出:连线;或打开连线模式在任意处拖',
          en: 'Drag from a pin: draw a wire — or turn on wire mode',
        ),
      ),
      (
        Icons.crop_free_rounded,
        tr(
          zh: '在空白处长按再拖:框选多个',
          en: 'Long-press empty space and drag: box-select',
        ),
      ),
      (
        Icons.pinch_rounded,
        tr(
          zh: '双指:缩放与平移;单指拖空白:平移',
          en: 'Two fingers: zoom and pan; one finger on empty space: pan',
        ),
      ),
      (
        Icons.play_circle_outline,
        tr(
          zh: '运行中点导线看电压,点元件看电流,点开关拨动',
          en: 'While running: tap a wire for voltage, a part for current, a switch to flip it',
        ),
      ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(zh: '手势', en: 'Gestures'),
              style: text.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final (icon, label) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: text.bodyMedium?.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Burst {
  _Burst(this.grid, this.color, this.born);

  final Offset grid;
  final Color color;
  final DateTime born;
}

/// Expanding rings and a flash at each fresh edit.
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.bursts, this.view);

  final List<_Burst> bursts;
  final CanvasView view;

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    for (final b in bursts) {
      final t = (now.difference(b.born).inMilliseconds / 520).clamp(0.0, 1.0);
      final e = Curves.easeOutCubic.transform(t);
      final c = view.toScreenXY(b.grid.dx, b.grid.dy);
      final r = view.scale * (0.3 + 1.6 * e);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - e) + 0.5
          ..color = b.color.withValues(alpha: 0.85 * (1 - e)),
      );
      canvas.drawCircle(
        c,
        view.scale * 0.5 * (1 - e),
        Paint()
          ..color = b.color.withValues(alpha: 0.35 * (1 - e))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => true;
}
