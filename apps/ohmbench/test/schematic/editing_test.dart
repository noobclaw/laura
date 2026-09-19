import 'package:flutter_test/flutter_test.dart';
import 'package:ohmbench/tool/schematic/document.dart';
import 'package:ohmbench/tool/schematic/editing.dart';

/// The six touch operations the App Store reviewers named, checked at the
/// model level so the widget layer only has to wire them up (see PLAN.md,
/// "M1 acceptance").
void main() {
  group('acceptance 1: place, then drag and rotate', () {
    test('a placed part can be dragged and lands on the grid', () {
      var doc = const SchematicDocument();
      late SchematicPart part;
      (doc, part) = doc.addPart(PartKind.resistor, const GridPoint(2, 2));

      const geometry = SchematicGeometry();
      final drag = DragSession(
        geometry: geometry,
        startX: 2,
        startY: 2,
        ids: {part.id},
      );
      doc = drag.update(doc, 5.4, 2.0);

      expect(drag.isMoving, isTrue);
      expect(doc.partById(part.id)!.origin, const GridPoint(5, 2));
    });

    test('rotating a selected part keeps it where it was', () {
      var doc = const SchematicDocument();
      late SchematicPart part;
      (doc, part) = doc.addPart(PartKind.diode, const GridPoint(6, 6));
      doc = doc.replacePart(doc.partById(part.id)!.rotated());
      expect(doc.partById(part.id)!.origin, const GridPoint(6, 6));
      expect(doc.partById(part.id)!.pins.first, const GridPoint(6, 6));
    });
  });

  group('acceptance 2: start a wire from an existing pin', () {
    test('a tap near a pin reports the pin, not the body', () {
      var doc = const SchematicDocument();
      (doc, _) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));

      const geometry = SchematicGeometry(pixelsPerGrid: 24);
      final hit = geometry.hitTest(doc, 0.2, 0.1);

      expect(hit, isA<PartHit>());
      expect((hit as PartHit).pinIndex, 0);
    });

    test('a tap on the body reports the body', () {
      var doc = const SchematicDocument();
      (doc, _) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));

      // Dead centre between the pins: one grid unit from either, which is
      // beyond the pin radius at this zoom.
      const geometry = SchematicGeometry(pixelsPerGrid: 24);
      final hit = geometry.hitTest(doc, 1.0, 0.0);

      expect(hit, isA<PartHit>());
      expect((hit as PartHit).pinIndex, isNull);
    });

    test('the touch target scales with zoom so it feels the same', () {
      var doc = const SchematicDocument();
      (doc, _) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));

      // Zoomed out, a pin covers fewer pixels — the forgiveness in *grid*
      // units has to grow to compensate, or the editor gets harder to use
      // exactly when parts are smallest.
      const far = SchematicGeometry(pixelsPerGrid: 8);
      const near = SchematicGeometry(pixelsPerGrid: 48);
      expect(far.touchRadiusInGrid, greaterThan(near.touchRadiusInGrid));
      expect(far.hitTest(doc, 1.0, 0.0), isA<PartHit>());
    });

    test('empty canvas reports the snapped point a new part would go to', () {
      const geometry = SchematicGeometry();
      final hit = geometry.hitTest(const SchematicDocument(), 3.4, -2.6);
      expect(hit, isA<EmptyHit>());
      expect((hit as EmptyHit).point, const GridPoint(3, -3));
    });
  });

  group('acceptance 3: a tap is never an accidental move', () {
    test('a wobble below the slop threshold leaves the document untouched', () {
      var doc = const SchematicDocument();
      late SchematicPart part;
      (doc, part) = doc.addPart(PartKind.resistor, const GridPoint(2, 2));
      final before = doc;

      const geometry = SchematicGeometry(pixelsPerGrid: 24);
      final drag = DragSession(
        geometry: geometry,
        startX: 2,
        startY: 2,
        ids: {part.id},
      );
      // 8 px of wobble at 24 px per grid = 0.33 grid, under the 12 px slop.
      doc = drag.update(doc, 2 + 8 / 24, 2 + 4 / 24);

      expect(drag.isMoving, isFalse);
      expect(identical(doc, before), isTrue);
      expect(drag.applied, (0, 0));
    });

    test('once armed, the drag follows the finger', () {
      var doc = const SchematicDocument();
      late SchematicPart part;
      (doc, part) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));

      final drag = DragSession(
        geometry: const SchematicGeometry(),
        startX: 0,
        startY: 0,
        ids: {part.id},
      );
      doc = drag.update(doc, 3, 0);
      doc = drag.update(doc, 3, 4);
      doc = drag.update(doc, 1, 1);

      expect(doc.partById(part.id)!.origin, const GridPoint(1, 1));
      expect(drag.applied, (1, 1));
    });
  });

  group('acceptance 4: marquee select and move together', () {
    test('a rectangle selects what is fully inside it', () {
      var doc = const SchematicDocument();
      late SchematicPart inside, outside;
      (doc, inside) = doc.addPart(PartKind.resistor, const GridPoint(1, 1));
      (doc, outside) = doc.addPart(PartKind.resistor, const GridPoint(20, 20));
      (doc, _) = doc.addWire(const GridPoint(1, 1), const GridPoint(3, 1));

      const geometry = SchematicGeometry();
      final ids = geometry.idsInRect(doc, 0, 0, 5, 5);

      expect(ids, contains(inside.id));
      expect(ids, contains('W3'));
      expect(ids, isNot(contains(outside.id)));
    });

    test('a selection moves as one rigid group', () {
      var doc = const SchematicDocument();
      late SchematicPart a, b;
      (doc, a) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));
      (doc, b) = doc.addPart(PartKind.capacitor, const GridPoint(0, 4));
      (doc, _) = doc.addWire(const GridPoint(0, 0), const GridPoint(0, 4));

      final moved = doc.moveIds({a.id, b.id, 'W3'}, 5, -2);

      expect(moved.partById(a.id)!.origin, const GridPoint(5, -2));
      expect(moved.partById(b.id)!.origin, const GridPoint(5, 2));
      expect(moved.wires.single.from, const GridPoint(5, -2));
      // Moving a whole net must not change what is connected to what.
      expect(moved.buildNetlist().netlist.devices.length,
          doc.buildNetlist().netlist.devices.length);
      expect(
        moved.buildNetlist().nodeOfPoint.values.toSet().length,
        doc.buildNetlist().nodeOfPoint.values.toSet().length,
      );
    });
  });

  group('acceptance 5: undo and redo, without a floor', () {
    test('every edit can be walked back and forward again', () {
      final history = EditHistory(const SchematicDocument());
      var doc = history.document;

      for (var i = 0; i < 40; i++) {
        late SchematicPart part;
        (doc, part) = doc.addPart(PartKind.resistor, GridPoint(i * 4, 0));
        history.push(doc, 'Add ${part.id}');
      }
      expect(history.document.parts.length, 40);

      for (var i = 0; i < 40; i++) {
        history.undo();
      }
      expect(history.document.parts, isEmpty);
      expect(history.canUndo, isFalse);

      for (var i = 0; i < 40; i++) {
        history.redo();
      }
      expect(history.document.parts.length, 40);
      expect(history.canRedo, isFalse);
    });

    test('an edit after an undo drops the redo branch', () {
      final history = EditHistory(const SchematicDocument());
      var doc = history.document;
      (doc, _) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));
      history.push(doc, 'Add R1');
      (doc, _) = doc.addPart(PartKind.capacitor, const GridPoint(4, 0));
      history.push(doc, 'Add C2');

      history.undo();
      expect(history.canRedo, isTrue);

      doc = history.document;
      (doc, _) = doc.addPart(PartKind.diode, const GridPoint(8, 0));
      history.push(doc, 'Add D2');

      expect(history.canRedo, isFalse);
      // The id counter is part of the snapshot, so undoing "Add C2" frees
      // the number 2 again. Nothing named C2 exists any more — the redo
      // branch went with it — so there is no collision to fear.
      expect(history.document.parts.map((p) => p.id), ['R1', 'D2']);
      expect(history.document.parts.map((p) => p.id).toSet().length, 2);
    });

    test('the button can say what it will undo', () {
      final history = EditHistory(const SchematicDocument());
      var doc = history.document;
      (doc, _) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));
      history.push(doc, 'Add R1');

      expect(history.undoLabel, 'Add R1');
      history.undo();
      expect(history.undoLabel, isNull);
      expect(history.redoLabel, 'Add R1');
    });

    test('beyond the memory guard the oldest state is dropped, not the newest',
        () {
      final history = EditHistory(const SchematicDocument(), limit: 5);
      var doc = history.document;
      for (var i = 0; i < 20; i++) {
        late SchematicPart part;
        (doc, part) = doc.addPart(PartKind.resistor, GridPoint(i * 4, 0));
        history.push(doc, 'Add ${part.id}');
      }

      expect(history.depth, 5);
      expect(history.document.parts.length, 20);
      // Four steps of history remain, and they are the four most recent.
      history.undo();
      expect(history.document.parts.length, 19);
    });

    test('loading a file resets history so undo cannot erase the file', () {
      final history = EditHistory(const SchematicDocument());
      var doc = history.document;
      (doc, _) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));
      history.push(doc, 'Add R1');

      var loaded = const SchematicDocument();
      (loaded, _) = loaded.addPart(PartKind.inductor, const GridPoint(0, 0));
      history.reset(loaded);

      expect(history.canUndo, isFalse);
      expect(history.document.parts.single.kind, PartKind.inductor);
    });
  });

  group('acceptance 6: deleting is also just an edit', () {
    test('a deleted part comes back with undo', () {
      final history = EditHistory(const SchematicDocument());
      var doc = history.document;
      late SchematicPart part;
      (doc, part) = doc.addPart(PartKind.resistor, const GridPoint(0, 0));
      history.push(doc, 'Add R1');

      doc = doc.removeIds({part.id});
      history.push(doc, 'Delete R1');
      expect(history.document.parts, isEmpty);

      history.undo();
      expect(history.document.partById('R1')!.origin, const GridPoint(0, 0));
    });
  });
}
