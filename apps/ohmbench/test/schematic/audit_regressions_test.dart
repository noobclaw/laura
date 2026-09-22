import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohmbench/tool/schematic/document.dart';
import 'package:ohmbench/tool/schematic/editing.dart';

/// Schematic-side regressions for the 2026-09-19 G2 audit.
void main() {
  group('P1-5: a part dropped on a wire is named, not silently shorted', () {
    test('both pins on one wire lands in shortedPartIds', () {
      var doc = const SchematicDocument();
      (doc, _) = doc.addWire(const GridPoint(0, 0), const GridPoint(6, 0));
      late SchematicPart r;
      (doc, r) = doc.addPart(PartKind.resistor, const GridPoint(2, 0));

      final build = doc.buildNetlist();

      expect(build.shortedPartIds, {r.id});
    });

    test('a part on the end of a wire (the T rule) is not flagged', () {
      var doc = const SchematicDocument();
      (doc, _) = doc.addWire(const GridPoint(0, 0), const GridPoint(2, 0));
      (doc, _) = doc.addPart(PartKind.resistor, const GridPoint(2, 0));

      expect(doc.buildNetlist().shortedPartIds, isEmpty);
    });
  });

  group('P1-6: impossible values are refused at the boundary', () {
    test('zero and negative R/C/L are reported and left out', () {
      var doc = const SchematicDocument();
      late SchematicPart r, c, l, ok;
      (doc, r) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));
      (doc, c) = doc.addPart(PartKind.capacitor, const GridPoint(0, 2));
      (doc, l) = doc.addPart(PartKind.inductor, const GridPoint(0, 4));
      (doc, ok) = doc.addPart(PartKind.resistor, const GridPoint(0, 6));
      doc = doc
          .replacePart(r.copyWith(value: -10))
          .replacePart(c.copyWith(value: 0))
          .replacePart(l.copyWith(value: double.nan));

      final build = doc.buildNetlist();

      expect(build.invalidPartIds, {r.id, c.id, l.id});
      expect(build.isRunnable, isFalse);
      expect(build.netlist.devices.map((d) => d.id), [ok.id]);
    });

    test('a negative supply is a real thing and is allowed', () {
      var doc = const SchematicDocument();
      late SchematicPart v;
      (doc, v) = doc.addPart(PartKind.dcSource, const GridPoint(0, 0));
      doc = doc.replacePart(v.copyWith(value: -12));

      expect(doc.buildNetlist().invalidPartIds, isEmpty);
    });
  });

  group('persistence guards', () {
    test('a non-finite value in a file falls back to the default', () {
      final json = jsonDecode(
          '{"parts":[{"id":"R1","kind":"resistor","x":0,"y":0,"value":"inf"}]}')
          as Map<String, dynamic>;

      final doc = SchematicDocument.fromJson(json);

      expect(doc.parts.single.value, PartKind.resistor.defaultValue);
    });

    test('copyWith can reset a value to the default', () {
      var doc = const SchematicDocument();
      late SchematicPart r;
      (doc, r) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));
      final typed = r.copyWith(value: 47);

      expect(typed.copyWith(resetValue: true).valueOverride, isNull);
      expect(typed.copyWith(rotation: 1).valueOverride, 47);
    });
  });

  group('P2-12: arming a drag does not jump a cell', () {
    test('the first armed frame leaves the part where it was', () {
      var doc = const SchematicDocument();
      late SchematicPart part;
      (doc, part) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));
      // Zoomed out: 12 px per cell, so the 12 px slop is a whole cell and
      // the spike moved the part one cell the instant the drag armed.
      final drag = DragSession(
        geometry: const SchematicGeometry(pixelsPerGrid: 12),
        startX: 0,
        startY: 0,
        ids: {part.id},
      );

      doc = drag.update(doc, 1.05, 0);

      expect(doc.partById(part.id)!.origin, const GridPoint(0, 0));
      doc = drag.update(doc, 2.2, 0);
      expect(doc.partById(part.id)!.origin, const GridPoint(1, 0));
    });
  });

  group('live runs continue where the last one stopped', () {
    test('initial conditions and a time offset reach the netlist', () {
      var doc = const SchematicDocument();
      late SchematicPart c, v;
      (doc, c) = doc.addPart(PartKind.capacitor, const GridPoint(0, 0));
      (doc, v) = doc.addPart(PartKind.sineSource, const GridPoint(0, 2));
      doc = doc.replacePart(v.copyWith(secondaryValue: 50));

      final build = doc.buildNetlist(
          initialVolts: {c.id: 3.3}, timeOffset: 0.005); // quarter period

      final cap = build.netlist.devices.firstWhere((d) => d.id == c.id);
      final src = build.netlist.devices.firstWhere((d) => d.id == v.id);
      expect((cap as dynamic).initialVolts, 3.3);
      expect(((src as dynamic).waveform as dynamic).phaseDegrees,
          closeTo(90, 1e-9));
    });
  });

  test('the touch target scales with zoom and still names the pin', () {
    var doc = const SchematicDocument();
    (doc, _) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));
    // 22 px radius at 44 px/cell = half a cell; the far pin is at x = 2.
    final hit = const SchematicGeometry(pixelsPerGrid: 44)
        .hitTest(doc, 1.6, 0.1);

    expect(hit, isA<PartHit>());
    expect((hit as PartHit).pinIndex, 1);
  });
}
