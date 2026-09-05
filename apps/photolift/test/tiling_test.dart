import 'package:flutter_test/flutter_test.dart';
import 'package:photolift/tool/tiling.dart';

void main() {
  group('fitInput', () {
    test('leaves small images alone', () {
      expect(fitInput(1200, 800, 4), const IntSize(1200, 800));
      expect(fitInput(1200, 800, 2), const IntSize(1200, 800));
    });

    test('caps 4x output at the pixel budget', () {
      final f = fitInput(4000, 3000, 4);
      expect(f.pixels * 16, lessThanOrEqualTo(kMaxOutputPixels));
      // Aspect preserved within a pixel.
      expect((f.width / f.height - 4 / 3).abs(), lessThan(0.01));
      // 2x of the same photo fits without shrinking as much.
      final g = fitInput(4000, 3000, 2);
      expect(g.pixels, greaterThan(f.pixels));
      expect(g.pixels * 4, lessThanOrEqualTo(kMaxOutputPixels));
    });

    test('caps the long edge', () {
      final f = fitInput(9000, 100, 2);
      expect(f.width * 2, lessThanOrEqualTo(kMaxOutputLongEdge));
      expect(f.height, greaterThanOrEqualTo(1));
    });

    test('degenerate sizes', () {
      expect(fitInput(0, 10, 2), const IntSize(0, 0));
      expect(fitInput(1, 1, 4), const IntSize(1, 1));
    });
  });

  group('planTiles', () {
    test('count matches tileCount and covers the image exactly once', () {
      for (final (w, h) in [(1, 1), (191, 192), (192, 192), (193, 500), (1000, 700)]) {
        final tiles = planTiles(w, h, kTileCpu, kTileOverlap);
        expect(tiles.length, tileCount(w, h, kTileCpu), reason: '$w x $h');
        final covered = List.filled(w * h, 0);
        for (final t in tiles) {
          for (var y = t.y0; y < t.y1; y++) {
            for (var x = t.x0; x < t.x1; x++) {
              covered[y * w + x]++;
            }
          }
        }
        expect(covered.every((c) => c == 1), isTrue, reason: '$w x $h coverage');
      }
    });

    test('read window plus padding always equals tile plus 2*overlap', () {
      final tiles = planTiles(500, 300, 192, 12);
      for (final t in tiles) {
        final readW = t.readX1 - t.readX0;
        final readH = t.readY1 - t.readY0;
        expect(readW + t.padLeft + t.padRight, t.width + 24);
        expect(readH + t.padTop + t.padBottom, t.height + 24);
        expect(t.readX0, greaterThanOrEqualTo(0));
        expect(t.readY0, greaterThanOrEqualTo(0));
        expect(t.readX1, lessThanOrEqualTo(500));
        expect(t.readY1, lessThanOrEqualTo(300));
        // Padding is only needed at the image border.
        if (t.x0 > 0) expect(t.padLeft, 0);
        if (t.y0 > 0) expect(t.padTop, 0);
        if (t.x1 < 500) expect(t.padRight, 0);
        if (t.y1 < 300) expect(t.padBottom, 0);
      }
    });

    test('interior tile is fully padded by neighbours', () {
      final tiles = planTiles(600, 600, 192, 12);
      final mid = tiles.firstWhere((t) => t.x0 == 192 && t.y0 == 192);
      expect(mid.padLeft + mid.padTop + mid.padRight + mid.padBottom, 0);
      expect(mid.readX0, 180);
      expect(mid.readX1, 396);
    });

    test('empty for degenerate input', () {
      expect(planTiles(0, 10, 192, 12), isEmpty);
      expect(tileCount(10, 0, 192), 0);
    });
  });
}
