import 'dart:math' as math;

import '../engine/linear_system.dart';
import '../engine/netlist.dart' show kGroundNode;
import '../schematic/document.dart';

/// One straight piece of drawn wire between two electrically interesting
/// points (wire ends and pins that sit on it).
class FlowSegment {
  const FlowSegment(this.a, this.b, this.node);

  final GridPoint a;
  final GridPoint b;
  final String node;

  double get length {
    final dx = (b.x - a.x).toDouble();
    final dy = (b.y - a.y).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// How current divides along the drawn wires.
///
/// The solver only knows nodes; a node drawn as a T or a loop of wire has no
/// single "wire current". To animate charge along the copper we solve a
/// second, tiny problem per node: every wire piece is a conductor whose
/// conductance is inversely proportional to its drawn length, and every pin
/// on the node injects the current of its part. That is what real copper of
/// uniform gauge does, so the dots split at a junction the way a real
/// current would, and they always satisfy Kirchhoff's current law.
class FlowGraph {
  FlowGraph._(this.segments, this._nets);

  final List<FlowSegment> segments;
  final List<_Net> _nets;

  /// Builds the graph for a drawing whose nodes are [nodeOfPoint].
  factory FlowGraph.build(
      SchematicDocument doc, Map<GridPoint, String> nodeOfPoint) {
    final points = <GridPoint>{
      for (final w in doc.wires) ...[w.from, w.to],
      for (final p in doc.parts) ...p.pins,
    };

    final seen = <String>{};
    final segments = <FlowSegment>[];
    for (final wire in doc.wires) {
      final on = points.where(wire.contains).toList()
        ..sort((p, q) => _along(wire, p).compareTo(_along(wire, q)));
      for (var i = 0; i + 1 < on.length; i++) {
        final a = on[i];
        final b = on[i + 1];
        if (a == b) continue;
        // Overlapping wires would otherwise double a segment.
        final key = _pairKey(a, b);
        if (!seen.add(key)) continue;
        final node = nodeOfPoint[a];
        if (node == null) continue;
        segments.add(FlowSegment(a, b, node));
      }
    }

    // Group segment indices and their points per node.
    final nets = <String, _Net>{};
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final net = nets.putIfAbsent(s.node, () => _Net(s.node));
      net.segmentIndices.add(i);
      net.indexOf(s.a);
      net.indexOf(s.b);
    }
    for (final part in doc.parts) {
      if (part.kind != PartKind.ground) continue;
      final pin = part.pins.first;
      final net = nets[nodeOfPoint[pin]];
      if (net != null && net.pointIndex.containsKey(pin)) {
        net.groundTaps.add(net.pointIndex[pin]!);
      }
    }
    return FlowGraph._(segments, nets.values.toList());
  }

  static double _along(SchematicWire w, GridPoint p) =>
      ((p.x - w.from.x) * (w.to.x - w.from.x) +
              (p.y - w.from.y) * (w.to.y - w.from.y))
          .toDouble();

  static String _pairKey(GridPoint a, GridPoint b) {
    final first = (a.y < b.y || (a.y == b.y && a.x <= b.x)) ? a : b;
    final second = identical(first, a) ? b : a;
    return '${first.x},${first.y}:${second.x},${second.y}';
  }

  /// Current along each segment, from `a` to `b`, given each part's current
  /// (anode to cathode, i.e. first pin to last pin).
  List<double> currents(
      SchematicDocument doc, double Function(String partId) partCurrent) {
    final out = List<double>.filled(segments.length, 0);

    // Injection into each wire point from the parts touching it. Current
    // enters a part at its first pin, so the wire loses it there, and gets
    // it back at the last pin.
    final injection = <GridPoint, double>{};
    for (final part in doc.parts) {
      if (part.kind == PartKind.ground) continue;
      final pins = part.pins;
      final i = partCurrent(part.id);
      if (i == 0 || !i.isFinite) continue;
      injection[pins.first] = (injection[pins.first] ?? 0) - i;
      injection[pins.last] = (injection[pins.last] ?? 0) + i;
    }

    for (final net in _nets) {
      final n = net.points.length;
      if (n == 0) continue;
      final system = MnaSystem(n);
      for (final index in net.segmentIndices) {
        final s = segments[index];
        final g = 1 / math.max(s.length, 1e-6);
        system.stampConductance(net.pointIndex[s.a]!, net.pointIndex[s.b]!, g);
      }
      // A faint tie from every point to a common reference keeps islands of
      // wire solvable; the ground symbols of node 0 are that reference, so
      // current can leave the drawing through them as it does in the circuit.
      for (var i = 0; i < n; i++) {
        system.addMatrix(i, i, 1e-9);
        system.addRhs(i, injection[net.points[i]] ?? 0);
      }
      if (net.node == kGroundNode) {
        for (final tap in net.groundTaps) {
          system.addMatrix(tap, tap, 1e3);
        }
      }
      final v = system.solve();
      if (v == null) continue;
      for (final index in net.segmentIndices) {
        final s = segments[index];
        final g = 1 / math.max(s.length, 1e-6);
        out[index] = g * (v[net.pointIndex[s.a]!] - v[net.pointIndex[s.b]!]);
      }
    }
    return out;
  }
}

class _Net {
  _Net(this.node);

  final String node;
  final List<GridPoint> points = [];
  final Map<GridPoint, int> pointIndex = {};
  final List<int> segmentIndices = [];
  final List<int> groundTaps = [];

  int indexOf(GridPoint p) =>
      pointIndex.putIfAbsent(p, () {
        points.add(p);
        return points.length - 1;
      });
}
