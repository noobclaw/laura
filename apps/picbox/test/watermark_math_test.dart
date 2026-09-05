import 'package:flutter_test/flutter_test.dart';
import 'package:picbox/tool/engine/watermark_math.dart';

void main() {
  group('font & margin', () {
    test('font size is a percent of the short side, floored at 8 px', () {
      expect(watermarkFontPx(3000, 5), 150);
      expect(watermarkFontPx(100, 1), 8);
      expect(watermarkFontPx(1000, 99), 300); // clamped to 30 %
    });
    test('margin', () {
      expect(watermarkMarginPx(3000, 3), 90);
      expect(watermarkMarginPx(3000, 0), 0);
    });
  });

  group('anchorOffset', () {
    const w = 1000;
    const h = 500;
    const sw = 200;
    const sh = 50;
    const m = 20;
    ({int x, int y}) at(WatermarkAnchor a) =>
        anchorOffset(w: w, h: h, spriteW: sw, spriteH: sh, margin: m, anchor: a);

    test('corners respect the margin', () {
      expect(at(WatermarkAnchor.topLeft), (x: 20, y: 20));
      expect(at(WatermarkAnchor.topRight), (x: 780, y: 20));
      expect(at(WatermarkAnchor.bottomLeft), (x: 20, y: 430));
      expect(at(WatermarkAnchor.bottomRight), (x: 780, y: 430));
    });
    test('centres', () {
      expect(at(WatermarkAnchor.center), (x: 400, y: 225));
      expect(at(WatermarkAnchor.topCenter), (x: 400, y: 20));
      expect(at(WatermarkAnchor.centerRight), (x: 780, y: 225));
      expect(at(WatermarkAnchor.bottomCenter), (x: 400, y: 430));
      expect(at(WatermarkAnchor.centerLeft), (x: 20, y: 225));
    });
    test('a sprite wider than the image is clamped to the canvas', () {
      final o = anchorOffset(w: 100, h: 100, spriteW: 300, spriteH: 20, margin: 10, anchor: WatermarkAnchor.bottomRight);
      expect(o, (x: 0, y: 70));
    });
  });

  group('tiling', () {
    test('covers the whole canvas including edges', () {
      final pos = tilePositions(w: 1000, h: 600, spriteW: 200, spriteH: 50);
      expect(pos, isNotEmpty);
      // Starts before the canvas so partial marks cover the edges…
      expect(pos.any((p) => p.x < 0), isTrue);
      expect(pos.any((p) => p.y < 0), isTrue);
      // …and reaches the far edges (last column/row starts within one
      // pitch of the edge: pitchX = 250, pitchY = 100).
      expect(pos.map((p) => p.x).reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(1000 - 250));
      expect(pos.map((p) => p.y).reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(600 - 100));
      // Marks never overlap: pitch is at least the sprite size.
      final xs = pos.where((p) => p.y == pos.first.y).map((p) => p.x).toList()..sort();
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i] - xs[i - 1], greaterThanOrEqualTo(200));
      }
    });
    test('alternate rows are staggered', () {
      final pos = tilePositions(w: 1000, h: 600, spriteW: 200, spriteH: 50);
      final rows = pos.map((p) => p.y).toSet().toList()..sort();
      final r0 = pos.where((p) => p.y == rows[0]).map((p) => p.x).toSet();
      final r1 = pos.where((p) => p.y == rows[1]).map((p) => p.x).toSet();
      expect(r0.intersection(r1), isEmpty);
    });
    test('degenerate sprite yields nothing', () {
      expect(tilePositions(w: 100, h: 100, spriteW: 0, spriteH: 10), isEmpty);
    });
  });

  test('rotatedBounds', () {
    expect(rotatedBounds(200, 50, 0), (width: 200, height: 50));
    expect(rotatedBounds(200, 50, 90), (width: 50, height: 200));
    final r = rotatedBounds(200, 50, 45);
    expect(r.width, 177);
    expect(r.height, 177);
  });

  test('spec round-trips through json', () {
    const s = WatermarkSpec(text: '©', anchor: WatermarkAnchor.topCenter, sizePercent: 7, opacity: 0.35, colorArgb: 0xFF112233, tiled: true, tileAngleDeg: 20, marginPercent: 5, shadow: false);
    final b = WatermarkSpec.fromJson(s.toJson());
    expect(b.text, '©');
    expect(b.anchor, WatermarkAnchor.topCenter);
    expect(b.sizePercent, 7);
    expect(b.opacity, 0.35);
    expect(b.colorArgb, 0xFF112233);
    expect(b.tiled, isTrue);
    expect(b.tileAngleDeg, 20);
    expect(b.marginPercent, 5);
    expect(b.shadow, isFalse);
  });
}
