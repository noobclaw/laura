/// The drawing the user actually touches: parts on a grid, wires between
/// them, and the rule that turns the two into a netlist.
///
/// Everything here is integer grid coordinates. Floating-point positions are
/// what make a part "almost" connected — the single most common way a
/// touch-drawn schematic silently fails to simulate — so positions snap on
/// the way in and are never stored as anything else.
library;

import '../engine/engine.dart';

/// A point on the schematic grid.
class GridPoint {
  const GridPoint(this.x, this.y);

  final int x;
  final int y;

  GridPoint translate(int dx, int dy) => GridPoint(x + dx, y + dy);

  @override
  bool operator ==(Object other) =>
      other is GridPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x,$y)';
}

/// What a part is. The engine's device types plus ground, which is a marker
/// rather than a device.
enum PartKind {
  resistor,
  capacitor,
  inductor,
  diode,
  dcSource,
  sineSource,
  currentSource,
  toggleSwitch,
  ground,
}

extension PartKindInfo on PartKind {
  /// Pin offsets from the part's origin, before rotation. Every device is two
  /// grid cells long, which keeps the body drawable at any rotation without
  /// re-measuring.
  List<GridPoint> get pinOffsets => switch (this) {
        PartKind.ground => const [GridPoint(0, 0)],
        _ => const [GridPoint(0, 0), GridPoint(2, 0)],
      };

  /// Default parameter, in SI units (ohms, farads, henries, volts, amps).
  double get defaultValue => switch (this) {
        PartKind.resistor => 1000,
        PartKind.capacitor => 1e-6,
        PartKind.inductor => 1e-3,
        PartKind.dcSource => 5,
        PartKind.sineSource => 5,
        PartKind.currentSource => 1e-3,
        PartKind.diode => 0,
        PartKind.toggleSwitch => 0,
        PartKind.ground => 0,
      };

  String get prefix => switch (this) {
        PartKind.resistor => 'R',
        PartKind.capacitor => 'C',
        PartKind.inductor => 'L',
        PartKind.diode => 'D',
        PartKind.dcSource => 'V',
        PartKind.sineSource => 'V',
        PartKind.currentSource => 'I',
        PartKind.toggleSwitch => 'S',
        PartKind.ground => 'GND',
      };
}

/// One placed part. Immutable: every edit produces a new instance, which is
/// what makes the undo stack a list of cheap snapshots rather than a pile of
/// inverse operations that have to be got exactly right.
class SchematicPart {
  const SchematicPart({
    required this.id,
    required this.kind,
    required this.origin,
    this.rotation = 0,
    this.valueOverride,
    this.secondaryValue = 1000,
    this.closed = true,
  });

  final String id;
  final PartKind kind;
  final GridPoint origin;

  /// Quarter turns clockwise, 0-3.
  final int rotation;

  /// The value the user typed, or null while the part still carries its
  /// default. Kept apart from [value] so that changing a default in a later
  /// version updates every part the user never touched.
  final double? valueOverride;

  /// Frequency in hertz for a sine source; unused otherwise.
  final double secondaryValue;

  /// Switch position.
  final bool closed;

  double get value => valueOverride ?? kind.defaultValue;

  /// Absolute positions of this part's pins, rotation applied.
  List<GridPoint> get pins => [
        for (final offset in kind.pinOffsets)
          _rotate(offset).translate(origin.x, origin.y),
      ];

  GridPoint _rotate(GridPoint p) => switch (rotation & 3) {
        1 => GridPoint(-p.y, p.x),
        2 => GridPoint(-p.x, -p.y),
        3 => GridPoint(p.y, -p.x),
        _ => p,
      };

  SchematicPart copyWith({
    GridPoint? origin,
    int? rotation,
    double? value,
    double? secondaryValue,
    bool? closed,
  }) =>
      SchematicPart(
        id: id,
        kind: kind,
        origin: origin ?? this.origin,
        rotation: rotation ?? this.rotation,
        valueOverride: value ?? valueOverride,
        secondaryValue: secondaryValue ?? this.secondaryValue,
        closed: closed ?? this.closed,
      );

  SchematicPart movedBy(int dx, int dy) =>
      copyWith(origin: origin.translate(dx, dy));

  /// Rotates about the part's own origin, so a part turns where it sits
  /// instead of walking across the canvas — one of the two complaints behind
  /// "moving them seems impossible".
  SchematicPart rotated() => copyWith(rotation: (rotation + 1) & 3);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'x': origin.x,
        'y': origin.y,
        'rot': rotation,
        if (valueOverride != null) 'value': valueOverride,
        'f': secondaryValue,
        'closed': closed,
      };

  static SchematicPart fromJson(Map<String, dynamic> json) => SchematicPart(
        id: json['id'] as String,
        kind: PartKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => PartKind.resistor,
        ),
        origin: GridPoint((json['x'] as num).toInt(), (json['y'] as num).toInt()),
        rotation: (json['rot'] as num?)?.toInt() ?? 0,
        valueOverride: (json['value'] as num?)?.toDouble(),
        secondaryValue: (json['f'] as num?)?.toDouble() ?? 1000,
        closed: json['closed'] as bool? ?? true,
      );
}

/// A drawn wire. Wires carry no electrical value; they only merge nodes.
class SchematicWire {
  const SchematicWire({required this.id, required this.from, required this.to});

  final String id;
  final GridPoint from;
  final GridPoint to;

  SchematicWire movedBy(int dx, int dy) => SchematicWire(
        id: id,
        from: from.translate(dx, dy),
        to: to.translate(dx, dy),
      );

  /// True when [p] sits on this wire, endpoints included. Only horizontal,
  /// vertical and 45-degree wires can be drawn, so an exact integer test is
  /// enough — no tolerance, no "almost on the wire".
  bool contains(GridPoint p) {
    final dx = to.x - from.x;
    final dy = to.y - from.y;
    final px = p.x - from.x;
    final py = p.y - from.y;
    if (dx == 0 && dy == 0) return px == 0 && py == 0;
    if (px * dy != py * dx) return false; // not collinear
    final dot = px * dx + py * dy;
    if (dot < 0) return false;
    return dot <= dx * dx + dy * dy;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'x1': from.x,
        'y1': from.y,
        'x2': to.x,
        'y2': to.y,
      };

  static SchematicWire fromJson(Map<String, dynamic> json) => SchematicWire(
        id: json['id'] as String,
        from: GridPoint(
            (json['x1'] as num).toInt(), (json['y1'] as num).toInt()),
        to: GridPoint((json['x2'] as num).toInt(), (json['y2'] as num).toInt()),
      );
}

/// The result of turning a drawing into something the solver can chew on.
class NetlistBuild {
  const NetlistBuild({
    required this.netlist,
    required this.nodeOfPoint,
    required this.hasGround,
  });

  final Netlist netlist;

  /// Which node each pin/wire point ended up in — what the UI colours by
  /// voltage, and what a probe tap looks up.
  final Map<GridPoint, String> nodeOfPoint;

  /// False when the user forgot a ground symbol. The solver would still
  /// answer (every node floats to its shunt), but the answer would be
  /// meaningless, so the UI says so instead of drawing nonsense.
  final bool hasGround;
}

/// A whole drawing.
class SchematicDocument {
  const SchematicDocument({
    this.parts = const [],
    this.wires = const [],
    this.nextId = 1,
  });

  final List<SchematicPart> parts;
  final List<SchematicWire> wires;

  /// Monotonic counter behind generated ids; part of the document so that
  /// undo cannot hand out an id that is already in use.
  final int nextId;

  bool get isEmpty => parts.isEmpty && wires.isEmpty;

  SchematicDocument copyWith({
    List<SchematicPart>? parts,
    List<SchematicWire>? wires,
    int? nextId,
  }) =>
      SchematicDocument(
        parts: parts ?? this.parts,
        wires: wires ?? this.wires,
        nextId: nextId ?? this.nextId,
      );

  SchematicPart? partById(String id) {
    for (final p in parts) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Adds a part at [origin], returning the new document and the new part.
  (SchematicDocument, SchematicPart) addPart(PartKind kind, GridPoint origin) {
    final part = SchematicPart(
      id: '${kind.prefix}$nextId',
      kind: kind,
      origin: origin,
    );
    return (
      copyWith(parts: [...parts, part], nextId: nextId + 1),
      part,
    );
  }

  (SchematicDocument, SchematicWire) addWire(GridPoint from, GridPoint to) {
    final wire = SchematicWire(id: 'W$nextId', from: from, to: to);
    return (
      copyWith(wires: [...wires, wire], nextId: nextId + 1),
      wire,
    );
  }

  SchematicDocument replacePart(SchematicPart part) => copyWith(
        parts: [
          for (final p in parts) p.id == part.id ? part : p,
        ],
      );

  SchematicDocument removeIds(Set<String> ids) => copyWith(
        parts: [for (final p in parts) if (!ids.contains(p.id)) p],
        wires: [for (final w in wires) if (!ids.contains(w.id)) w],
      );

  /// Moves every element in [ids] by the same offset.
  SchematicDocument moveIds(Set<String> ids, int dx, int dy) => copyWith(
        parts: [
          for (final p in parts) ids.contains(p.id) ? p.movedBy(dx, dy) : p,
        ],
        wires: [
          for (final w in wires) ids.contains(w.id) ? w.movedBy(dx, dy) : w,
        ],
      );

  // ------------------------------------------------------------ connectivity

  /// Merges pins and wire ends into electrical nodes and emits a [Netlist].
  ///
  /// Two points are the same node when they coincide, when a wire joins them,
  /// or when one of them lands anywhere along a wire — the T-junction case.
  /// Requiring the user to hit an endpoint exactly is what makes touch
  /// schematic editors feel like a fight; here the wire's whole length is a
  /// terminal.
  NetlistBuild buildNetlist() {
    final union = _UnionFind();

    for (final wire in wires) {
      union.union(wire.from, wire.to);
    }

    // Every point that can be electrically interesting.
    final points = <GridPoint>{
      for (final w in wires) ...[w.from, w.to],
      for (final p in parts) ...p.pins,
    };

    // A point sitting on a wire joins that wire's net; this also covers two
    // wires crossing at a shared endpoint and a pin dropped mid-wire.
    for (final wire in wires) {
      for (final point in points) {
        if (wire.contains(point)) union.union(point, wire.from);
      }
    }

    // Ground pins all become node '0'.
    final groundRoots = <GridPoint>{};
    for (final part in parts) {
      if (part.kind == PartKind.ground) {
        groundRoots.add(union.find(part.pins.first));
      }
    }

    final names = <GridPoint, String>{};
    var counter = 1;
    String nameFor(GridPoint p) {
      final root = union.find(p);
      if (groundRoots.contains(root)) return kGroundNode;
      return names[root] ??= 'n${counter++}';
    }

    // Deterministic order: the node numbering must not depend on hash order,
    // or a saved drawing would read back with different node names.
    final ordered = points.toList()
      ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    final nodeOfPoint = <GridPoint, String>{
      for (final p in ordered) p: nameFor(p),
    };

    final devices = <Device>[];
    for (final part in parts) {
      if (part.kind == PartKind.ground) continue;
      final pins = part.pins;
      final a = nodeOfPoint[pins.first]!;
      final b = nodeOfPoint[pins.last]!;
      devices.add(switch (part.kind) {
        PartKind.resistor =>
          Resistor(id: part.id, anode: a, cathode: b, ohms: part.value),
        PartKind.capacitor =>
          Capacitor(id: part.id, anode: a, cathode: b, farads: part.value),
        PartKind.inductor =>
          Inductor(id: part.id, anode: a, cathode: b, henries: part.value),
        PartKind.diode => Diode(id: part.id, anode: a, cathode: b),
        PartKind.dcSource => VoltageSource(
            id: part.id,
            anode: a,
            cathode: b,
            waveform: DcWaveform(part.value),
          ),
        PartKind.sineSource => VoltageSource(
            id: part.id,
            anode: a,
            cathode: b,
            waveform: SineWaveform(
              amplitude: part.value,
              frequencyHz: part.secondaryValue,
            ),
          ),
        PartKind.currentSource => CurrentSource(
            id: part.id,
            anode: a,
            cathode: b,
            waveform: DcWaveform(part.value),
          ),
        PartKind.toggleSwitch => SwitchDevice(
            id: part.id,
            anode: a,
            cathode: b,
            closed: part.closed,
          ),
        PartKind.ground => throw StateError('ground is not a device'),
      });
    }

    return NetlistBuild(
      netlist: Netlist(devices),
      nodeOfPoint: nodeOfPoint,
      hasGround: groundRoots.isNotEmpty,
    );
  }

  // ------------------------------------------------------------ persistence

  Map<String, dynamic> toJson() => {
        'version': 1,
        'nextId': nextId,
        'parts': [for (final p in parts) p.toJson()],
        'wires': [for (final w in wires) w.toJson()],
      };

  static SchematicDocument fromJson(Map<String, dynamic> json) {
    final parts = <SchematicPart>[];
    for (final raw in (json['parts'] as List? ?? const [])) {
      parts.add(SchematicPart.fromJson(raw as Map<String, dynamic>));
    }
    final wires = <SchematicWire>[];
    for (final raw in (json['wires'] as List? ?? const [])) {
      wires.add(SchematicWire.fromJson(raw as Map<String, dynamic>));
    }
    // A file written by a newer build may hold ids we would otherwise reuse;
    // start the counter above anything present rather than trusting the field.
    var next = (json['nextId'] as num?)?.toInt() ?? 1;
    for (final element in [...parts.map((p) => p.id), ...wires.map((w) => w.id)]) {
      final digits = RegExp(r'(\d+)$').firstMatch(element)?.group(1);
      final n = digits == null ? 0 : int.tryParse(digits) ?? 0;
      if (n >= next) next = n + 1;
    }
    return SchematicDocument(parts: parts, wires: wires, nextId: next);
  }
}

/// Disjoint sets over grid points, path-compressed.
class _UnionFind {
  final Map<GridPoint, GridPoint> _parent = {};

  GridPoint find(GridPoint p) {
    var root = _parent[p] ?? p;
    if (root == p) {
      _parent[p] = p;
      return p;
    }
    root = find(root);
    _parent[p] = root;
    return root;
  }

  void union(GridPoint a, GridPoint b) {
    final ra = find(a);
    final rb = find(b);
    if (ra == rb) return;
    // Lowest coordinate wins, so the representative of a net does not depend
    // on the order the user drew things in.
    if (ra.y < rb.y || (ra.y == rb.y && ra.x <= rb.x)) {
      _parent[rb] = ra;
    } else {
      _parent[ra] = rb;
    }
  }
}
