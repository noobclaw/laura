// Cross-checks against the reference projects listed in REFERENCE.md.
//
// astroalign (MIT): the `test_find_transform_givensources` numbers are taken
// verbatim from its tests/test_align.py, and the synthetic-image tests follow
// its `simulate_image_pair` idea (random stars, Gaussian PSF, known
// similarity between the two frames).
// astra_lite (MIT): FWHM / ovality of the common star image.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:astropile/tool/engine/asterism.dart';
import 'package:astropile/tool/engine/quality.dart';
import 'package:astropile/tool/engine/stars.dart';
import 'package:astropile/tool/engine/transform.dart';
import 'package:flutter_test/flutter_test.dart';

/// One synthetic star: centroid and peak amplitude above the sky.
typedef Planted = (double x, double y, double peak);

/// Render a night sky: Gaussian PSF stars on a background with Gaussian
/// noise. [trail] draws each star as a short horizontal streak instead of a
/// disc (a hand-held frame that moved during the exposure).
Uint8List renderSky(
  int w,
  int h,
  List<Planted> stars, {
  double sigma = 1.4,
  int background = 18,
  double noiseSd = 1.5,
  int seed = 1,
  double trail = 0,
}) {
  final rng = math.Random(seed);
  final luma = Uint8List(w * h);
  for (var i = 0; i < luma.length; i++) {
    // Box–Muller.
    final u1 = 1 - rng.nextDouble();
    final u2 = rng.nextDouble();
    final n = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    luma[i] = (background + n * noiseSd).round().clamp(0, 255);
  }
  final radius = (3.5 * sigma + trail).ceil();
  final twoSigma2 = 2 * sigma * sigma;
  for (final s in stars) {
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final x = s.$1.round() + dx;
        final y = s.$2.round() + dy;
        if (x < 0 || y < 0 || x >= w || y >= h) continue;
        // Distance to the (possibly trailed) star centre line.
        var ddx = x - s.$1;
        final ddy = y - s.$2;
        if (trail > 0) ddx = (ddx.abs() - trail / 2).clamp(0.0, double.infinity);
        final v = s.$3 * math.exp(-(ddx * ddx + ddy * ddy) / twoSigma2);
        final i = y * w + x;
        luma[i] = (luma[i] + v).round().clamp(0, 255);
      }
    }
  }
  return luma;
}

List<Planted> randomField(int n, int w, int h, int seed, {double margin = 20}) {
  final rng = math.Random(seed);
  final out = <Planted>[];
  var guard = 0;
  while (out.length < n && guard < n * 500) {
    guard++;
    final x = margin + rng.nextDouble() * (w - 2 * margin);
    final y = margin + rng.nextDouble() * (h - 2 * margin);
    if (out.any((p) => (p.$1 - x).abs() < 22 && (p.$2 - y).abs() < 22)) continue;
    out.add((x, y, 90 + rng.nextDouble() * 90));
  }
  return out;
}

/// The frame's stars moved by [t], keeping only the ones still in frame.
List<Planted> moved(List<Planted> ref, Similarity t, int w, int h) => [
      for (final s in ref)
        if (t.apply(s.$1, s.$2) case final p when p.$1 > 8 && p.$2 > 8 && p.$1 < w - 8 && p.$2 < h - 8)
          (p.$1, p.$2, s.$3),
    ];

/// Exactly what pipeline._alignFrame decides for one frame; null = aligned.
AlignFailure? verdict(StarField frame, StarField ref) {
  if (frame.overloaded) return AlignFailure.tooBright;
  if (frame.stars.length < 3) return AlignFailure.tooFewStars;
  try {
    alignStars(frame.stars, ref.stars);
    return null;
  } on AlignException catch (e) {
    return e.failure;
  }
}

List<Star> starsAt(List<(double, double)> pts) =>
    [for (var i = 0; i < pts.length; i++) Star(pts[i].$1, pts[i].$2, 1000 - i.toDouble(), 9)];

void main() {
  group('astroalign cross-check', () {
    test('find_transform on the given-sources case recovers 1.5x / pi/8 / (2,1)', () {
      // tests/test_align.py::test_find_transform_givensources
      const source = <(double, double)>[
        (1.4, 2.2),
        (5.3, 1.0),
        (3.7, 1.5),
        (10.1, 9.6),
        (1.3, 10.2),
        (7.1, 2.0),
      ];
      const scale = 1.5;
      final alpha = math.pi / 8;
      const tx = 2.0, ty = 1.0;
      final c = scale * math.cos(alpha);
      final d = scale * math.sin(alpha);
      final truth = Similarity(c, d, tx, ty);
      final dest = [for (final p in source) truth.apply(p.$1, p.$2)]..shuffle(math.Random(3));

      // The reference project has no plausibility gate, so widen ours to run
      // its 1.5× / 22.5° case through the same code path.
      final res = alignStars(starsAt(source), starsAt(dest),
          minScale: 0.5, maxScale: 2.0, maxRotationDegrees: 90);
      expect(res.transform.scale, closeTo(scale, 1e-6));
      expect(res.transform.rotationDegrees, closeTo(22.5, 1e-6));
      expect(res.transform.tx, closeTo(tx, 1e-6));
      expect(res.transform.ty, closeTo(ty, 1e-6));
      expect(res.matchedStars, source.length);
      expect(res.rmsPixels, lessThan(1e-6));
    });

    test('invariants are [L3/L2, L2/L1] with vertices ordered a=L1∩L2, b=L2∩L3, c=L3∩L1', () {
      // A 3-4-5 triangle: L1=3 (p0-p1), L2=4 (p1-p2), L3=5 (p2-p0).
      final pts = starsAt([(0, 0), (3, 0), (3, 4)]);
      final ast = buildAsterisms(pts).single;
      expect(ast.r1, closeTo(5 / 4, 1e-12));
      expect(ast.r2, closeTo(4 / 3, 1e-12));
      expect(ast.a, 1); // joins the 3 and the 4
      expect(ast.b, 2); // joins the 4 and the 5
      expect(ast.c, 0); // joins the 5 and the 3
    });
  });

  group('synthetic frames (astroalign simulate_image_pair idea)', () {
    const w = 900;
    const h = 700;
    final ref = randomField(45, w, h, 41);
    // 3° roll, a 6 % zoom and a hand-held shift.
    const scale = 1.06;
    final theta = 3.0 * math.pi / 180;
    final truth = Similarity(scale * math.cos(theta), scale * math.sin(theta), 17.3, -9.6);
    final refLuma = renderSky(w, h, ref, seed: 11);
    final refField = detectStars(refLuma, w, h);

    test('the planted field is detected cleanly', () {
      expect(refField.overloaded, isFalse);
      expect(refField.stars.length, greaterThanOrEqualTo(40));
    });

    test('rotation + translation + scale is recovered to < 0.5 px and < 0.1°', () {
      final frame = renderSky(w, h, moved(ref, truth, w, h), seed: 12);
      final field = detectStars(frame, w, h);
      final res = alignStars(field.stars, refField.stars);

      // res.transform maps the moved frame back onto the reference, so it
      // must undo `truth` everywhere, including at the corners.
      for (final p in const [(0.0, 0.0), (w - 1.0, 0.0), (0.0, h - 1.0), (w - 1.0, h - 1.0), (450.0, 350.0)]) {
        final q = truth.apply(p.$1, p.$2);
        final back = res.transform.apply(q.$1, q.$2);
        expect(back.$1, closeTo(p.$1, 0.5), reason: 'x at $p');
        expect(back.$2, closeTo(p.$2, 0.5), reason: 'y at $p');
      }
      expect(res.transform.rotationDegrees, closeTo(-3.0, 0.1));
      expect(res.transform.scale, closeTo(1 / scale, 0.002));
      expect(res.matchedStars, greaterThanOrEqualTo(20));
      expect(res.rmsPixels, lessThan(0.5));
    });

    test('a frame drowned in noise is rejected with a star-count reason', () {
      final noisy = renderSky(w, h, moved(ref, truth, w, h), seed: 13, noiseSd: 45);
      final v = verdict(detectStars(noisy, w, h), refField);
      expect(v, isNotNull);
      expect(
          v,
          isIn([
            AlignFailure.tooFewStars,
            AlignFailure.noMatch,
            AlignFailure.tooFewMatches,
            AlignFailure.highResidual,
          ]));
    });

    test('a frame with two stars is rejected as tooFewStars', () {
      final sparse = renderSky(w, h, moved(ref, truth, w, h).take(2).toList(), seed: 14);
      expect(verdict(detectStars(sparse, w, h), refField), AlignFailure.tooFewStars);
    });

    test('a frame of a different patch of sky finds no matching asterism', () {
      final elsewhere = renderSky(w, h, randomField(45, w, h, 99), seed: 15);
      final v = verdict(detectStars(elsewhere, w, h), refField);
      expect(v, isIn([AlignFailure.noMatch, AlignFailure.tooFewMatches, AlignFailure.highResidual]));
    });
  });

  group('astra_lite star shape', () {
    const w = 600;
    const h = 500;
    final planted = randomField(30, w, h, 7);

    test('FWHM of a Gaussian PSF is about 2.355 sigma', () {
      final luma = renderSky(w, h, planted, sigma: 1.4, seed: 21);
      final f = detectStars(luma, w, h);
      final shape = measureStarShape(luma, w, h, f.stars, f.background);
      expect(shape.measured, isTrue);
      expect(shape.sampled, greaterThanOrEqualTo(20));
      expect(shape.fwhm, closeTo(2.355 * 1.4, 0.8));
      expect(shape.hfd, greaterThan(0));
      expect(shape.ovality, lessThan(1.0));
    });

    test('a defocused frame measures twice as fat and trips the blur gate', () {
      final sharp = renderSky(w, h, planted, sigma: 1.4, seed: 22);
      final soft = renderSky(w, h, planted, sigma: 3.5, seed: 23);
      final fs = detectStars(sharp, w, h);
      final fb = detectStars(soft, w, h);
      final a = measureStarShape(sharp, w, h, fs.stars, fs.background);
      final b = measureStarShape(soft, w, h, fb.stars, fb.background);
      expect(b.fwhm / a.fwhm, greaterThan(2.0));
      expect(isBlurry(b.fwhm, a.fwhm), isTrue);
      expect(isBlurry(a.fwhm, b.fwhm), isFalse);
      expect(isBlurry(a.fwhm, a.fwhm), isFalse);
      // Unmeasured never rejects.
      expect(isBlurry(0, a.fwhm), isFalse);
      expect(isBlurry(b.fwhm, 0), isFalse);
    });

    test('trailed stars show up as elongation', () {
      final round = renderSky(w, h, planted, sigma: 1.4, seed: 24);
      final trailed = renderSky(w, h, planted, sigma: 1.4, seed: 25, trail: 6);
      final fr = detectStars(round, w, h);
      final ft = detectStars(trailed, w, h);
      final a = measureStarShape(round, w, h, fr.stars, fr.background);
      final b = measureStarShape(trailed, w, h, ft.stars, ft.background);
      expect(b.ovality, greaterThan(a.ovality + 2.0));
    });

    test('no stars, or only saturated ones, is reported as unmeasured', () {
      expect(measureStarShape(Uint8List(100), 10, 10, const [], 5).measured, isFalse);
      final luma = Uint8List(40 * 40)..fillRange(0, 40 * 40, 10);
      for (var y = 18; y < 23; y++) {
        for (var x = 18; x < 23; x++) {
          luma[y * 40 + x] = 255;
        }
      }
      final f = detectStars(luma, 40, 40);
      expect(measureStarShape(luma, 40, 40, f.stars, f.background).measured, isFalse);
    });
  });
}
