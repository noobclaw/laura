/// Editing state around a [SchematicDocument]: history, selection, and the
/// arithmetic behind touch gestures.
///
/// The two complaints this file answers, in the reviewers' words:
/// "moving them seems impossible" (drags snap, and only start past a slop
/// threshold so a tap is never a move), and "I feel like I am fighting the
/// program instead of using it" (every edit is one undo away from gone).
library;

import 'dart:math' as math;

import 'document.dart';

/// How far a finger must travel before a tap becomes a drag, in logical
/// pixels. Below this, the gesture is a selection — a 2 mm wobble while
/// tapping a part must not nudge it off its wire.
const double kDragSlopPixels = 12;

/// Radius around a finger that counts as touching a pin or a wire, in
/// logical pixels. Apple's minimum target is 44 pt; half of it is the radius
/// that makes a 1 px wire catchable without swallowing its neighbours.
const double kTouchRadiusPixels = 22;

/// One entry of edit history.
class _HistoryEntry {
  const _HistoryEntry(this.document, this.label);

  final SchematicDocument document;

  /// Shown on the undo button ("Undo move"), so the user knows what will go.
  final String label;
}

/// An undo stack over whole-document snapshots.
///
/// Snapshots rather than inverse commands: a schematic that fits on a phone
/// screen is a few kilobytes, and an inverse-command stack is exactly where
/// "undo sometimes corrupts my circuit" bugs live. [limit] is a memory guard,
/// not a feature — at 512 entries a hundred-part drawing costs a few MB.
class EditHistory {
  EditHistory(SchematicDocument initial, {this.limit = 512})
      : _entries = [_HistoryEntry(initial, '')];

  final List<_HistoryEntry> _entries;
  final int limit;
  int _cursor = 0;

  SchematicDocument get document => _entries[_cursor].document;

  bool get canUndo => _cursor > 0;

  bool get canRedo => _cursor < _entries.length - 1;

  /// Label of the edit that [undo] would take back, or null.
  String? get undoLabel => canUndo ? _entries[_cursor].label : null;

  /// Label of the edit that [redo] would put back, or null.
  String? get redoLabel => canRedo ? _entries[_cursor + 1].label : null;

  int get depth => _entries.length;

  /// Records [next] as a new state. Anything that had been undone is dropped,
  /// which is what every editor does and what users expect.
  void push(SchematicDocument next, String label) {
    if (_cursor < _entries.length - 1) {
      _entries.removeRange(_cursor + 1, _entries.length);
    }
    _entries.add(_HistoryEntry(next, label));
    if (_entries.length > limit) {
      _entries.removeAt(0);
    } else {
      _cursor++;
    }
  }

  SchematicDocument undo() {
    if (canUndo) _cursor--;
    return document;
  }

  SchematicDocument redo() {
    if (canRedo) _cursor++;
    return document;
  }

  /// Replaces the whole history — used when a document is loaded from disk,
  /// so the first undo cannot take the user back to an empty canvas they
  /// never saw.
  void reset(SchematicDocument document) {
    _entries
      ..clear()
      ..add(_HistoryEntry(document, ''));
    _cursor = 0;
  }
}

/// What the finger landed on.
sealed class HitResult {
  const HitResult();
}

class PartHit extends HitResult {
  const PartHit(this.part, this.pinIndex);

  final SchematicPart part;

  /// The pin under the finger, or null when the body was hit. Pins win over
  /// bodies: starting a wire from a pin is the gesture reviewers said they
  /// could not perform.
  final int? pinIndex;
}

class WireHit extends HitResult {
  const WireHit(this.wire);

  final SchematicWire wire;
}

class EmptyHit extends HitResult {
  const EmptyHit(this.point);

  final GridPoint point;
}

/// Turns finger positions into document coordinates and back.
///
/// [pixelsPerGrid] is the current zoom. All tolerances are declared in
/// pixels and converted here, so pinching does not change how forgiving the
/// editor feels — the bug behind "the gate menu sucks... I have to tap a
/// button near the top and then another near the bottom" is the same family:
/// tolerances that were tuned at one zoom level and wrong at every other.
class SchematicGeometry {
  const SchematicGeometry({this.pixelsPerGrid = 24});

  final double pixelsPerGrid;

  GridPoint snap(double px, double py) => GridPoint(
        (px / pixelsPerGrid).round(),
        (py / pixelsPerGrid).round(),
      );

  double get touchRadiusInGrid => kTouchRadiusPixels / pixelsPerGrid;

  double get dragSlopInGrid => kDragSlopPixels / pixelsPerGrid;

  /// Hit test in document units, nearest first: pins, then wires, then part
  /// bodies, then empty canvas.
  HitResult hitTest(SchematicDocument document, double gx, double gy) {
    final radius = touchRadiusInGrid;
    HitResult? best;
    var bestDistance = double.infinity;

    for (final part in document.parts) {
      final pins = part.pins;
      for (var i = 0; i < pins.length; i++) {
        final d = _distance(gx, gy, pins[i].x.toDouble(), pins[i].y.toDouble());
        if (d <= radius && d < bestDistance) {
          bestDistance = d;
          best = PartHit(part, i);
        }
      }
    }
    if (best != null) return best;

    for (final wire in document.wires) {
      final d = _distanceToSegment(gx, gy, wire.from, wire.to);
      if (d <= radius && d < bestDistance) {
        bestDistance = d;
        best = WireHit(wire);
      }
    }

    for (final part in document.parts) {
      final pins = part.pins;
      final d = pins.length == 1
          ? _distance(gx, gy, pins.first.x.toDouble(), pins.first.y.toDouble())
          : _distanceToSegment(gx, gy, pins.first, pins.last);
      if (d <= radius && d < bestDistance) {
        bestDistance = d;
        best = PartHit(part, null);
      }
    }

    return best ?? EmptyHit(GridPoint(gx.round(), gy.round()));
  }

  /// Ids fully inside a marquee, in document units.
  Set<String> idsInRect(
      SchematicDocument document, double x1, double y1, double x2, double y2) {
    final left = x1 < x2 ? x1 : x2;
    final right = x1 < x2 ? x2 : x1;
    final top = y1 < y2 ? y1 : y2;
    final bottom = y1 < y2 ? y2 : y1;
    bool inside(GridPoint p) =>
        p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;

    return {
      for (final part in document.parts)
        if (part.pins.every(inside)) part.id,
      for (final wire in document.wires)
        if (inside(wire.from) && inside(wire.to)) wire.id,
    };
  }

  static double _distance(double x, double y, double px, double py) {
    final dx = x - px;
    final dy = y - py;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _distanceToSegment(
      double x, double y, GridPoint from, GridPoint to) {
    final dx = (to.x - from.x).toDouble();
    final dy = (to.y - from.y).toDouble();
    if (dx == 0 && dy == 0) {
      return _distance(x, y, from.x.toDouble(), from.y.toDouble());
    }
    var t = ((x - from.x) * dx + (y - from.y) * dy) / (dx * dx + dy * dy);
    t = t.clamp(0.0, 1.0);
    return _distance(x, y, from.x + dx * t, from.y + dy * t);
  }
}

/// A drag in progress.
///
/// The state machine exists so that the "did the user mean to move this?"
/// decision lives in one testable place instead of being spread across
/// gesture callbacks. Until the finger passes the slop threshold the document
/// is untouched, so a tap that wobbles selects instead of moving — the
/// mis-touch protection the reviews asked for.
class DragSession {
  DragSession({
    required this.geometry,
    required this.startX,
    required this.startY,
    required this.ids,
  });

  final SchematicGeometry geometry;
  final double startX;
  final double startY;

  /// Everything that moves together: one part, or a whole marquee selection.
  final Set<String> ids;

  bool _armed = false;
  int _appliedDx = 0;
  int _appliedDy = 0;

  /// True once the gesture has committed to being a move.
  bool get isMoving => _armed;

  /// Feeds a new finger position and returns the document to display.
  /// Positions snap, so a part that started on a node stays on the grid it
  /// started on rather than drifting a fraction of a cell per drag.
  SchematicDocument update(SchematicDocument document, double x, double y) {
    final dx = x - startX;
    final dy = y - startY;
    if (!_armed) {
      final slop = geometry.dragSlopInGrid;
      if (dx.abs() < slop && dy.abs() < slop) return document;
      _armed = true;
    }
    final snappedDx = dx.round();
    final snappedDy = dy.round();
    if (snappedDx == _appliedDx && snappedDy == _appliedDy) return document;
    final moved = document.moveIds(
        ids, snappedDx - _appliedDx, snappedDy - _appliedDy);
    _appliedDx = snappedDx;
    _appliedDy = snappedDy;
    return moved;
  }

  /// Net displacement applied so far; zero means nothing changed and the
  /// caller should not push an undo entry.
  (int, int) get applied => (_appliedDx, _appliedDy);
}
