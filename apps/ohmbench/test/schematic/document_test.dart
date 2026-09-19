import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohmbench/tool/engine/engine.dart';
import 'package:ohmbench/tool/schematic/document.dart';

/// Connectivity and persistence: the bridge between what the user draws and
/// what the solver runs, plus "my work is still there after the app was
/// killed" (acceptance item 6).
void main() {
  group('pins and rotation', () {
    test('a part rotates about its own origin, four turns return it home', () {
      const part = SchematicPart(
          id: 'R1', kind: PartKind.resistor, origin: GridPoint(4, 4));

      expect(part.pins, [const GridPoint(4, 4), const GridPoint(6, 4)]);

      final once = part.rotated();
      expect(once.origin, const GridPoint(4, 4));
      expect(once.pins, [const GridPoint(4, 4), const GridPoint(4, 6)]);

      final full = part.rotated().rotated().rotated().rotated();
      expect(full.pins, part.pins);
      expect(full.origin, part.origin);
    });

    test('moving is exact on the grid, and reversible', () {
      const part = SchematicPart(
          id: 'C1', kind: PartKind.capacitor, origin: GridPoint(0, 0));
      final there = part.movedBy(7, -3);
      final back = there.movedBy(-7, 3);
      expect(there.origin, const GridPoint(7, -3));
      expect(back.origin, part.origin);
    });
  });

  group('wires become nodes', () {
    test('a divider drawn with wires solves to the same numbers as a netlist',
        () {
      // 10 V source, two resistors, ground — drawn the way a finger would.
      var doc = const SchematicDocument();
      late SchematicPart source, r1, r2, gnd;
      (doc, source) = doc.addPart(PartKind.dcSource, const GridPoint(0, 0));
      (doc, r1) = doc.addPart(PartKind.resistor, const GridPoint(4, 0));
      (doc, r2) = doc.addPart(PartKind.resistor, const GridPoint(8, 0));
      (doc, gnd) = doc.addPart(PartKind.ground, const GridPoint(2, 0));
      doc = doc
          .replacePart(source.copyWith(value: 10))
          .replacePart(r1.copyWith(value: 2000))
          .replacePart(r2.copyWith(value: 3000));
      // The source's + pin is (0,0) and its - pin (2,0), where the ground
      // symbol sits. The top rail routes around the negative pin rather than
      // straight through it: a wire laid over that pin would short the
      // source, which is exactly what the T-junction rule is supposed to do.
      (doc, _) = doc.addWire(const GridPoint(0, 0), const GridPoint(0, -2));
      (doc, _) = doc.addWire(const GridPoint(0, -2), const GridPoint(4, -2));
      (doc, _) = doc.addWire(const GridPoint(4, -2), const GridPoint(4, 0));
      (doc, _) = doc.addWire(const GridPoint(6, 0), const GridPoint(8, 0));
      (doc, _) = doc.addWire(const GridPoint(10, 0), const GridPoint(10, 4));
      (doc, _) = doc.addWire(const GridPoint(10, 4), const GridPoint(2, 4));
      (doc, _) = doc.addWire(const GridPoint(2, 4), const GridPoint(2, 0));

      final build = doc.buildNetlist();
      expect(build.hasGround, isTrue);
      expect(build.netlist.devices.length, 3);

      final op = CircuitSolver(build.netlist).operatingPoint();
      expect(op.converged, isTrue);
      expect(op.notes, isNot(contains(SolverNote.floatingNodesTiedToGround)));

      final midNode = build.nodeOfPoint[const GridPoint(6, 0)]!;
      final topNode = build.nodeOfPoint[const GridPoint(0, 0)]!;
      expect(op.voltageAt(topNode), closeTo(10, 1e-9));
      expect(op.voltageAt(midNode), closeTo(6, 1e-9));
      expect(gnd.kind, PartKind.ground);
    });

    test('a pin dropped on the middle of a wire joins it (T junction)', () {
      var doc = const SchematicDocument();
      (doc, _) = doc.addWire(const GridPoint(0, 0), const GridPoint(10, 0));
      // Resistor hanging down from the middle of that wire.
      late SchematicPart r;
      (doc, r) = doc.addPart(PartKind.resistor, const GridPoint(5, 0));
      doc = doc.replacePart(r.copyWith(rotation: 1));

      final build = doc.buildNetlist();
      final wireNode = build.nodeOfPoint[const GridPoint(0, 0)]!;
      final pinNode = build.nodeOfPoint[const GridPoint(5, 0)]!;
      expect(pinNode, wireNode,
          reason: 'landing anywhere on a wire must connect, '
              'not only on its endpoints');
      // The far end of the rotated resistor is its own node.
      expect(build.nodeOfPoint[const GridPoint(5, 2)], isNot(wireNode));
    });

    test('wires that merely cross are not connected', () {
      var doc = const SchematicDocument();
      (doc, _) = doc.addWire(const GridPoint(0, 0), const GridPoint(10, 0));
      (doc, _) = doc.addWire(const GridPoint(5, -5), const GridPoint(5, 5));

      final build = doc.buildNetlist();
      // The crossing point is not an endpoint of the horizontal wire, but it
      // is a point of the vertical one — SPICE-style schematics treat only
      // endpoints as terminals, so these two nets stay apart.
      expect(build.nodeOfPoint[const GridPoint(0, 0)],
          isNot(build.nodeOfPoint[const GridPoint(5, -5)]));
    });

    test('node numbering does not depend on drawing order', () {
      SchematicDocument draw(bool reversed) {
        var doc = const SchematicDocument();
        final points = [
          [const GridPoint(0, 0), const GridPoint(4, 0)],
          [const GridPoint(4, 0), const GridPoint(4, 4)],
        ];
        for (final pair in reversed ? points.reversed : points) {
          (doc, _) = doc.addWire(pair[0], pair[1]);
        }
        late SchematicPart r;
        (doc, r) = doc.addPart(PartKind.resistor, const GridPoint(4, 4));
        return doc.replacePart(r);
      }

      final forward = draw(false).buildNetlist();
      final backward = draw(true).buildNetlist();
      expect(forward.nodeOfPoint[const GridPoint(0, 0)],
          backward.nodeOfPoint[const GridPoint(0, 0)]);
      expect(forward.nodeOfPoint[const GridPoint(6, 4)],
          backward.nodeOfPoint[const GridPoint(6, 4)]);
    });

    test('a drawing with no ground is reported, not silently simulated', () {
      var doc = const SchematicDocument();
      (doc, _) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));
      expect(doc.buildNetlist().hasGround, isFalse);
    });

    test('a part left floating still simulates, with a warning', () {
      var doc = const SchematicDocument();
      late SchematicPart source, r, gnd;
      (doc, source) = doc.addPart(PartKind.dcSource, const GridPoint(0, 0));
      (doc, gnd) = doc.addPart(PartKind.ground, const GridPoint(0, 0));
      (doc, r) = doc.addPart(PartKind.resistor, const GridPoint(20, 20));
      (doc, _) = doc.addWire(const GridPoint(2, 0), const GridPoint(2, 4));
      doc = doc.replacePart(source).replacePart(gnd).replacePart(r);

      final build = doc.buildNetlist();
      final op = CircuitSolver(build.netlist).operatingPoint();
      expect(op.converged, isTrue);
      expect(op.notes, contains(SolverNote.floatingNodesTiedToGround));
    });
  });

  group('persistence', () {
    test('a document survives a save and reload byte for byte', () {
      var doc = const SchematicDocument();
      late SchematicPart r, v;
      (doc, r) = doc.addPart(PartKind.resistor, const GridPoint(3, 5));
      (doc, v) = doc.addPart(PartKind.sineSource, const GridPoint(0, 0));
      doc = doc
          .replacePart(r.copyWith(value: 4700, rotation: 3))
          .replacePart(v.copyWith(value: 12, secondaryValue: 50));
      (doc, _) = doc.addWire(const GridPoint(0, 0), const GridPoint(3, 5));

      final encoded = jsonEncode(doc.toJson());
      final reloaded =
          SchematicDocument.fromJson(jsonDecode(encoded) as Map<String, dynamic>);

      expect(jsonEncode(reloaded.toJson()), encoded);
      expect(reloaded.partById('R1')!.value, 4700);
      expect(reloaded.partById('R1')!.rotation, 3);
      expect(reloaded.partById('V2')!.secondaryValue, 50);
      // And it still means the same circuit.
      expect(reloaded.buildNetlist().netlist.devices.length,
          doc.buildNetlist().netlist.devices.length);
    });

    test('ids are never reissued after a reload', () {
      var doc = const SchematicDocument();
      (doc, _) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));
      (doc, _) = doc.addPart(PartKind.resistor, const GridPoint(4, 0));

      // A file whose counter was lost or written by an older build.
      final json = doc.toJson()..remove('nextId');
      final reloaded = SchematicDocument.fromJson(json);
      late SchematicPart fresh;
      (_, fresh) = reloaded.addPart(PartKind.resistor, const GridPoint(8, 0));

      expect(reloaded.parts.map((p) => p.id), ['R1', 'R2']);
      expect(fresh.id, 'R3');
    });

    test('a damaged file yields an empty document, not a crash', () {
      final doc = SchematicDocument.fromJson(
          jsonDecode('{"version":1}') as Map<String, dynamic>);
      expect(doc.isEmpty, isTrue);
      expect(doc.buildNetlist().netlist.devices, isEmpty);
    });
  });
}
