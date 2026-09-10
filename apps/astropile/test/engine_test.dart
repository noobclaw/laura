import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:astropile/tool/engine/asterism.dart';
import 'package:astropile/tool/engine/stack.dart';
import 'package:astropile/tool/engine/stars.dart';
import 'package:astropile/tool/engine/stretch.dart';
import 'package:astropile/tool/engine/transform.dart';
import 'package:astropile/tool/engine/warp.dart';
import 'package:flutter_test/flutter_test.dart';

/// Paint a Gaussian-ish disc so the detector sees something with a real
/// centroid rather than a single hot pixel.
void _paintStar(Uint8List luma, int w, int h, double cx, double cy, int peak) {
  const radius = 3;
  for (var dy = -radius; dy <= radius; dy++) {
    for (var dx = -radius; dx <= radius; dx++) {
      final x = (cx + dx).round();
      final y = (cy + dy).round();
      if (x < 0 || y < 0 || x >= w || y >= h) continue;
      final r2 = (x - cx) * (x - cx) + (y - cy) * (y - cy);
      final v = (peak * math.exp(-r2 / 2.2)).round();
      final i = y * w + x;
      final sum = luma[i] + v;
      luma[i] = sum > 255 ? 255 : sum;
    }
  }
}

Uint8List _skyWith(List<(double, double)> stars, int w, int h, {int background = 18}) {
  final luma = Uint8List(w * h)..fillRange(0, w * h, background);
  // A touch of deterministic texture so the noise estimate is not exactly 0.
  final rng = math.Random(7);
  for (var i = 0; i < luma.length; i++) {
    luma[i] = (background + rng.nextInt(5) - 2).clamp(0, 255);
  }
  for (final s in stars) {
    _paintStar(luma, w, h, s.$1, s.$2, 180);
  }
  return luma;
}

List<(double, double)> _randomStars(int n, int w, int h, int seed) {
  final rng = math.Random(seed);
  final out = <(double, double)>[];
  var guard = 0;
  while (out.length < n && guard < n * 200) {
    guard++;
    final x = 12 + rng.nextDouble() * (w - 24);
    final y = 12 + rng.nextDouble() * (h - 24);
    // Keep stars apart so their discs never merge into one blob.
    if (out.any((p) => (p.$1 - x).abs() < 14 && (p.$2 - y).abs() < 14)) continue;
    out.add((x, y));
  }
  return out;
}

void main() {
  group('background estimation', () {
    test('finds the sky level and ignores the stars', () {
      final luma = _skyWith(_randomStars(20, 300, 300, 1), 300, 300);
      final bg = estimateBackground(luma);
      expect(bg.background, closeTo(18, 2));
      expect(bg.noise, greaterThanOrEqualTo(1.0));
    });

    test('a flat frame still reports a usable noise floor', () {
      final flat = Uint8List(10000)..fillRange(0, 10000, 40);
      final bg = estimateBackground(flat);
      expect(bg.background, closeTo(40, 0.001));
      expect(bg.noise, 1.0);
    });
  });

  group('star detection', () {
    test('recovers planted centroids to sub-pixel accuracy', () {
      final planted = _randomStars(15, 400, 400, 2);
      final luma = _skyWith(planted, 400, 400);
      final field = detectStars(luma, 400, 400);
      expect(field.overloaded, isFalse);
      expect(field.stars.length, planted.length);
      for (final p in planted) {
        final match = field.stars.reduce((a, b) {
          final da = (a.x - p.$1).abs() + (a.y - p.$2).abs();
          final db = (b.x - p.$1).abs() + (b.y - p.$2).abs();
          return da <= db ? a : b;
        });
        expect((match.x - p.$1).abs(), lessThan(0.6));
        expect((match.y - p.$2).abs(), lessThan(0.6));
      }
    });

    test('single hot pixels are below the minimum area', () {
      final luma = Uint8List(200 * 200)..fillRange(0, 200 * 200, 20);
      luma[50 * 200 + 50] = 255;
      luma[120 * 200 + 30] = 255;
      final field = detectStars(luma, 200, 200);
      expect(field.stars, isEmpty);
    });

    test('an all-white frame is reported as overloaded, not crashed', () {
      final luma = Uint8List(300 * 300);
      final rng = math.Random(3);
      for (var i = 0; i < luma.length; i++) {
        luma[i] = 200 + rng.nextInt(55);
      }
      // Alternating columns produce a run for every other pixel, which is
      // what "not a star field" looks like to the extractor.
      for (var i = 0; i < luma.length; i += 2) {
        luma[i] = 0;
      }
      final field = detectStars(luma, 300, 300, minArea: 1);
      expect(field.stars.length, lessThanOrEqualTo(kMaxControlPoints));
    });

    test('a blob larger than the area cap (the moon) is rejected', () {
      final luma = Uint8List(300 * 300)..fillRange(0, 300 * 300, 15);
      for (var y = 100; y < 200; y++) {
        for (var x = 100; x < 200; x++) {
          luma[y * 300 + x] = 240;
        }
      }
      final field = detectStars(luma, 300, 300);
      expect(field.stars, isEmpty);
    });
  });

  group('similarity transform', () {
    test('closed-form fit recovers a known transform', () {
      const truth = Similarity(0.99619, 0.08716, 12.5, -7.25); // ~5°, 1.0×
      final src = <(double, double)>[];
      final dst = <(double, double)>[];
      final rng = math.Random(11);
      for (var i = 0; i < 8; i++) {
        final x = rng.nextDouble() * 500;
        final y = rng.nextDouble() * 500;
        src.add((x, y));
        dst.add(truth.apply(x, y));
      }
      final fit = fitSimilarity(src, dst)!;
      expect(fit.c, closeTo(truth.c, 1e-6));
      expect(fit.d, closeTo(truth.d, 1e-6));
      expect(fit.tx, closeTo(truth.tx, 1e-6));
      expect(fit.ty, closeTo(truth.ty, 1e-6));
    });

    test('inverse undoes apply', () {
      const t = Similarity(1.02, -0.05, 30, 11);
      final p = t.apply(123.5, 88.25);
      final back = t.inverse(p.$1, p.$2);
      expect(back.$1, closeTo(123.5, 1e-9));
      expect(back.$2, closeTo(88.25, 1e-9));
    });

    test('degenerate input returns null instead of NaN', () {
      final fit = fitSimilarity(
        [(5, 5), (5, 5), (5, 5)],
        [(1, 1), (2, 2), (3, 3)],
      );
      expect(fit, isNull);
    });
  });

  group('asterism matching', () {
    List<Star> starsAt(List<(double, double)> pts) =>
        [for (final p in pts) Star(p.$1, p.$2, 1000 - pts.indexOf(p).toDouble(), 9)];

    test('recovers a shift and a small rotation', () {
      const truth = Similarity(0.99939, 0.03490, 9.0, -4.0); // 2°
      final ref = _randomStars(24, 800, 600, 5);
      final moved = [for (final p in ref) truth.apply(p.$1, p.$2)];
      final res = alignStars(starsAt(moved), starsAt(ref));
      // The recovered transform maps the moved frame back onto the reference,
      // so composing with the truth must land on identity.
      final probe = res.transform.apply(truth.apply(100, 100).$1, truth.apply(100, 100).$2);
      expect(probe.$1, closeTo(100, 0.5));
      expect(probe.$2, closeTo(100, 0.5));
      expect(res.matchedStars, greaterThanOrEqualTo(4));
      expect(res.rmsPixels, lessThan(kPixelTolerance));
      expect(res.score, greaterThan(60));
    });

    test('pure translation is recovered exactly', () {
      const truth = Similarity(1, 0, -23.5, 17.25);
      final ref = _randomStars(20, 700, 700, 9);
      final moved = [for (final p in ref) truth.apply(p.$1, p.$2)];
      final res = alignStars(starsAt(moved), starsAt(ref));
      expect(res.transform.tx, closeTo(23.5, 0.2));
      expect(res.transform.ty, closeTo(-17.25, 0.2));
      expect(res.transform.scale, closeTo(1, 0.002));
    });

    test('too few stars is reported as tooFewStars', () {
      expect(
        () => alignStars(starsAt([(1, 1), (5, 5)]), starsAt([(1, 1), (5, 5), (9, 2)])),
        throwsA(isA<AlignException>()
            .having((e) => e.failure, 'failure', AlignFailure.tooFewStars)),
      );
    });

    test('two unrelated fields do not produce a transform', () {
      final a = starsAt(_randomStars(20, 600, 600, 21));
      final b = starsAt(_randomStars(20, 600, 600, 77));
      expect(() => alignStars(a, b), throwsA(isA<AlignException>()));
    });

    test('an implausible scale is rejected rather than smeared', () {
      const wild = Similarity(2.0, 0, 0, 0);
      final ref = _randomStars(20, 600, 600, 31);
      final scaled = [for (final p in ref) wild.apply(p.$1, p.$2)];
      expect(
        () => alignStars(starsAt(scaled), starsAt(ref)),
        throwsA(isA<AlignException>()),
      );
    });
  });

  group('resampling', () {
    test('identity warp is a byte-for-byte copy', () {
      final src = Uint8List.fromList(List.generate(4 * 3 * 3, (i) => i % 251));
      final out = warpRgb(src, 4, 3, Similarity.identity);
      expect(out, src);
    });

    test('integer translation shifts pixels exactly', () {
      const w = 8;
      const h = 6;
      final src = Uint8List(w * h * 3);
      for (var i = 0; i < w * h; i++) {
        src[i * 3] = i; // red ramp
      }
      // Source pixel (x, y) lands on (x + 2, y + 1).
      final out = warpRgb(src, w, h, const Similarity(1, 0, 2, 1));
      expect(out[((1 * w) + 2) * 3], src[0]);
      expect(out[((3 * w) + 5) * 3], src[((2 * w) + 3) * 3]);
      // The uncovered left column stays black.
      expect(out[0], 0);
    });

    test('downsample by two averages each quad', () {
      final src = Uint8List.fromList([
        // 2×2 image, red channel 0/10/20/30
        0, 0, 0, 10, 0, 0, //
        20, 0, 0, 30, 0, 0,
      ]);
      final out = downsampleRgb(src, 2, 2, 2, outW: 1, outH: 1);
      expect(out[0], 15);
    });
  });

  group('coverage', () {
    test('identity covers the whole row', () {
      final r = rowCoverage(Similarity.identity, 100, 100, 100, 50);
      expect(r, (0, 99));
    });

    test('a translated frame leaves an uncovered margin', () {
      // Source pixels land 10 px to the right, so output column 0..9 has no
      // source behind it.
      final r = rowCoverage(const Similarity(1, 0, 10, 0), 100, 100, 100, 50);
      expect(r.$1, 10);
      expect(r.$2, 99);
    });

    test('a row entirely off the frame reports empty', () {
      final r = rowCoverage(const Similarity(1, 0, 0, 500), 100, 100, 100, 5);
      expect(r.$2 < r.$1, isTrue);
    });
  });

  group('stacking', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('astropile_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    AlignedFrame write(String name, List<int> bytes) {
      final p = '${dir.path}/$name';
      File(p).writeAsBytesSync(Uint8List.fromList(bytes));
      return AlignedFrame(
          path: p, transform: Similarity.identity, sourceWidth: 2, sourceHeight: 1);
    }

    test('mean averages every frame', () {
      final frames = [
        write('a.raw', [10, 20, 30, 40, 50, 60]),
        write('b.raw', [30, 40, 50, 60, 70, 80]),
      ];
      final out = stackBand(frames, 2, 0, 1, StackMode.mean);
      expect(out, [20, 30, 40, 50, 60, 70]);
    });

    test('median drops the outlier frame', () {
      final frames = [
        write('a.raw', [10, 10, 10, 10, 10, 10]),
        write('b.raw', [12, 12, 12, 12, 12, 12]),
        write('c.raw', [250, 250, 250, 250, 250, 250]), // an aircraft
      ];
      final mean = stackBand(frames, 2, 0, 1, StackMode.mean);
      final median = stackBand(frames, 2, 0, 1, StackMode.median);
      expect(median[0], 12);
      expect(mean[0], greaterThan(80));
    });

    test('uncovered pixels are skipped, not averaged as black', () {
      final a = write('a.raw', [100, 100, 100, 100, 100, 100]);
      final bPath = '${dir.path}/b.raw';
      File(bPath).writeAsBytesSync(Uint8List.fromList([0, 0, 0, 200, 200, 200]));
      // This frame only covers output column 1.
      final b = AlignedFrame(
        path: bPath,
        transform: const Similarity(1, 0, 1, 0),
        sourceWidth: 2,
        sourceHeight: 1,
      );
      final out = stackBand([a, b], 2, 0, 1, StackMode.mean);
      expect(out[0], 100); // column 0: only frame a
      expect(out[3], 150); // column 1: both
    });

    test('medianOf handles even and odd counts', () {
      expect(medianOf(Uint8List.fromList([5, 1, 3]), 3), 3);
      expect(medianOf(Uint8List.fromList([10, 20, 30, 40]), 4), 25);
    });
  });

  group('tone curve', () {
    test('mtf is anchored at 0, m and 1', () {
      expect(mtf(0.3, 0), 0);
      expect(mtf(0.3, 1), 1);
      expect(mtf(0.3, 0.3), closeTo(0.5, 1e-9));
    });

    test('midtoneFor inverts mtf', () {
      final m = midtoneFor(0.05, 0.25);
      expect(mtf(m, 0.05), closeTo(0.25, 1e-6));
    });

    test('the lut lifts the measured sky to the requested level', () {
      const params = StretchParams(black: 0, midtone: 0.25, saturation: 1);
      final lut = toneLut(params, 0.08);
      expect(lut[(0.08 * 255).round()], closeTo(0.25 * 255, 4));
      expect(lut[0], 0);
      expect(lut[255], 255);
    });

    test('the curve never inverts', () {
      final lut = toneLut(const StretchParams(black: 0.1, midtone: 0.4, saturation: 1), 0.15);
      for (var i = 1; i < 256; i++) {
        expect(lut[i], greaterThanOrEqualTo(lut[i - 1]));
      }
    });

    test('auto stretch stays inside the slider ranges', () {
      final rgb = Uint8List(300 * 3);
      for (var i = 0; i < 300; i++) {
        rgb[i * 3] = 20;
        rgb[i * 3 + 1] = 22;
        rgb[i * 3 + 2] = 25;
      }
      final p = autoStretch(measureTone(rgb));
      expect(p.black, inInclusiveRange(0, 0.9));
      expect(p.midtone, inInclusiveRange(0.03, 0.6));
      expect(p.saturation, inInclusiveRange(0, 2));
    });

    test('saturation of zero produces grey', () {
      final src = Uint8List.fromList([200, 60, 30]);
      final dest = Uint8List(3);
      applyStretch(src, dest, const StretchParams(black: 0, midtone: 0.5, saturation: 0), 0.5);
      expect(dest[0], dest[1]);
      expect(dest[1], dest[2]);
    });
  });
}
