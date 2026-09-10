import 'dart:math' as math;

import 'stars.dart';
import 'transform.dart';

/// Why one frame could not be aligned. Localised on the UI isolate — a
/// background isolate does not carry the user's language override.
enum AlignFailure {
  /// The frame decoded but has a different pixel size than the reference.
  sizeMismatch,

  /// More pixels than this device can decode without being killed.
  tooLarge,

  /// Stars were found on both frames, but too few of them agreed to solve a
  /// transform from.
  tooFewMatches,

  /// Fewer than three usable point sources — a cloudy frame, a lens cap, or
  /// a picture that is not of the night sky at all.
  tooFewStars,

  /// Detection gave up: the frame is mostly above the detection threshold.
  tooBright,

  /// Stars were found but no consistent asterism links the two frames.
  noMatch,

  /// A transform was found but the fit is worse than the pixel tolerance,
  /// or it is geometrically implausible for consecutive hand-held frames.
  highResidual,

  /// The file could not be decoded.
  decodeFailed,

}

/// Pixel residual under which a point pair counts as an inlier.
const double kPixelTolerance = 2.0;

/// Nearest neighbours (including the point itself) used to build asterisms.
const int kNeighbours = 5;

/// Fraction of candidate triangle matches that must agree before RANSAC
/// accepts a model; the effective threshold is capped at 10 triangles.
const double kMinMatchFraction = 0.8;

/// Radius in invariant space within which two asterisms are "the same shape".
const double kInvariantRadius = 0.1;

/// Maximum RANSAC minimal-sample trials. See [alignStars].
const int kRansacTrials = 250;

/// Plausibility bounds for consecutive frames of one session. A match that
/// implies the sky doubled in size or rolled 60° is a coincidence in
/// invariant space, not an alignment — and letting it through produces the
/// smeared output the free competitors are famous for.
const double kMinScale = 0.8;
const double kMaxScale = 1.25;
const double kMaxRotationDegrees = 45;

/// A triangle of control points, ordered so that the same physical asterism
/// gets the same vertex order in both frames.
class Asterism {
  const Asterism(this.a, this.b, this.c, this.r1, this.r2);

  /// Indices into the control-point list.
  final int a;
  final int b;
  final int c;

  /// Scale- and rotation-invariant shape descriptor: `L3/L2` and `L2/L1`
  /// for sides sorted `L1 ≤ L2 ≤ L3`.
  final double r1;
  final double r2;
}

/// Outcome of matching one frame against the reference.
class AlignResult {
  const AlignResult({
    required this.transform,
    required this.matchedStars,
    required this.rmsPixels,
  });

  final Similarity transform;

  /// Control points that survived to the final fit.
  final int matchedStars;

  /// Root-mean-square reprojection error of those points.
  final double rmsPixels;

  /// 0–100. 60 points for how many stars agreed (saturating at 20), 40 for
  /// how tightly they agreed. Presented to the user per frame, so it must
  /// move for reasons a person can act on: add more stars, or hold steadier.
  int get score {
    final matchPart = 60 * math.min(matchedStars, 20) / 20;
    final fitPart = 40 * math.max(0.0, 1 - rmsPixels / kPixelTolerance);
    return (matchPart + fitPart).round().clamp(0, 100);
  }
}

/// Thrown by [alignStars] so the caller can report a specific reason.
class AlignException implements Exception {
  AlignException(this.failure);
  final AlignFailure failure;
  @override
  String toString() => 'AlignException(${failure.name})';
}

/// Build the invariant descriptors for one set of control points.
///
/// For every point, the [kNeighbours] closest points (itself included) form
/// C(5,3) = 10 triangles; duplicates across neighbourhoods are dropped.
List<Asterism> buildAsterisms(List<Star> points) {
  final n = points.length;
  if (n < 3) return const [];
  final knn = math.min(n, kNeighbours);
  final out = <Asterism>[];
  final seen = <int>{};
  final dist = List<double>.filled(n, 0);
  final order = List<int>.generate(n, (i) => i);

  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      final dx = points[j].x - points[i].x;
      final dy = points[j].y - points[i].y;
      dist[j] = dx * dx + dy * dy;
      order[j] = j;
    }
    order.sort((p, q) => dist[p].compareTo(dist[q]));
    final near = order.sublist(0, knn);
    for (var p = 0; p < knn - 2; p++) {
      for (var q = p + 1; q < knn - 1; q++) {
        for (var r = q + 1; r < knn; r++) {
          final tri = [near[p], near[q], near[r]]..sort();
          // n ≤ 50 control points, so a packed triple fits an int safely.
          final key = (tri[0] * n + tri[1]) * n + tri[2];
          if (!seen.add(key)) continue;
          final ast = _arrange(points, tri[0], tri[1], tri[2]);
          if (ast != null) out.add(ast);
        }
      }
    }
  }
  return out;
}

/// Order a triple as (a, b, c) where a joins the two shortest sides, b the
/// two middle ones and c the two longest, then compute its invariants.
/// Returns null for degenerate triangles (coincident or collinear points).
Asterism? _arrange(List<Star> pts, int i1, int i2, int i3) {
  final d12 = _dist(pts[i1], pts[i2]);
  final d23 = _dist(pts[i2], pts[i3]);
  final d31 = _dist(pts[i3], pts[i1]);
  if (d12 <= 0 || d23 <= 0 || d31 <= 0) return null;

  // (length, the two endpoints of that side)
  final sides = <(double, int, int)>[(d12, i1, i2), (d23, i2, i3), (d31, i3, i1)];
  sides.sort((a, b) => a.$1.compareTo(b.$1));
  final l1 = sides[0].$1;
  final l2 = sides[1].$1;
  final l3 = sides[2].$1;
  if (l1 <= 1e-6 || l2 <= 1e-6) return null;

  final a = _sharedVertex(sides[0], sides[1]);
  final b = _sharedVertex(sides[1], sides[2]);
  final c = _sharedVertex(sides[2], sides[0]);
  if (a < 0 || b < 0 || c < 0) return null;
  return Asterism(a, b, c, l3 / l2, l2 / l1);
}

int _sharedVertex((double, int, int) p, (double, int, int) q) {
  if (p.$2 == q.$2 || p.$2 == q.$3) return p.$2;
  if (p.$3 == q.$2 || p.$3 == q.$3) return p.$3;
  return -1;
}

double _dist(Star a, Star b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// Estimate the transform taking [source] control points onto [target].
///
/// Throws [AlignException] with the specific reason on failure. [seed] fixes
/// the RANSAC shuffle so the same frames always produce the same result —
/// a stacker that gives a different answer on a re-run is impossible to
/// reason about when a frame is rejected.
AlignResult alignStars(List<Star> source, List<Star> target, {int seed = 20260908}) {
  if (source.length < 3 || target.length < 3) {
    throw AlignException(AlignFailure.tooFewStars);
  }
  final srcAst = buildAsterisms(source);
  final dstAst = buildAsterisms(target);
  if (srcAst.isEmpty || dstAst.isEmpty) {
    throw AlignException(AlignFailure.tooFewStars);
  }

  // Candidate correspondences: asterisms whose shape descriptors coincide.
  const r2 = kInvariantRadius * kInvariantRadius;
  final matches = <List<int>>[]; // [sa, ta, sb, tb, sc, tc]
  for (final s in srcAst) {
    for (final t in dstAst) {
      final dr1 = s.r1 - t.r1;
      final dr2 = s.r2 - t.r2;
      if (dr1 * dr1 + dr2 * dr2 <= r2) {
        matches.add([s.a, t.a, s.b, t.b, s.c, t.c]);
        if (matches.length >= 4000) break;
      }
    }
    if (matches.length >= 4000) break;
  }
  if (matches.isEmpty) throw AlignException(AlignFailure.noMatch);

  final minMatches = math.max(1, math.min(10, (matches.length * kMinMatchFraction).floor()));
  final rng = math.Random(seed);
  final idx = List<int>.generate(matches.length, (i) => i)..shuffle(rng);

  // Every trial scans all candidates, so an exhaustive search is quadratic —
  // and the exhaustive case is exactly the *failing* frame, where the user is
  // already waiting. Sampling caps that at a few hundred trials; with a real
  // match the first correct triangle usually lands in the first handful.
  final trials = math.min(idx.length, kRansacTrials);

  Similarity? best;
  for (final i in idx.take(trials)) {
    final model = _fitFromMatches(source, target, [matches[i]]);
    if (model == null) continue;
    final inliers = <List<int>>[];
    for (final m in matches) {
      if (_triangleError(source, target, m, model) < kPixelTolerance) inliers.add(m);
    }
    if (inliers.length >= minMatches) {
      best = _fitFromMatches(source, target, inliers);
      break;
    }
  }
  if (best == null) throw AlignException(AlignFailure.noMatch);

  // Refine: re-fit on everything the current model explains, three rounds.
  var model = best;
  var inliers = <List<int>>[];
  for (var round = 0; round < 3; round++) {
    inliers = [
      for (final m in matches)
        if (_triangleError(source, target, m, model) < kPixelTolerance) m,
    ];
    final refit = _fitFromMatches(source, target, inliers);
    if (refit == null) break;
    model = refit;
  }
  if (inliers.isEmpty) throw AlignException(AlignFailure.noMatch);

  // Collapse to unique point pairs. Deduping only on the source side lets
  // two source stars claim the same reference star, which drags the final
  // fit towards that point and inflates the reported match count, so the
  // target side is deduped too.
  final bestForSource = <int, (int, double)>{};
  for (final m in inliers) {
    for (var k = 0; k < 6; k += 2) {
      final si = m[k];
      final ti = m[k + 1];
      final p = model.apply(source[si].x, source[si].y);
      final dx = p.$1 - target[ti].x;
      final dy = p.$2 - target[ti].y;
      final err = math.sqrt(dx * dx + dy * dy);
      final prev = bestForSource[si];
      if (prev == null || err < prev.$2) bestForSource[si] = (ti, err);
    }
  }
  final bestForTarget = <int, (int, double)>{};
  bestForSource.forEach((si, e) {
    final prev = bestForTarget[e.$1];
    if (prev == null || e.$2 < prev.$2) bestForTarget[e.$1] = (si, e.$2);
  });
  if (bestForTarget.length < 3) throw AlignException(AlignFailure.tooFewMatches);

  final srcPts = <(double, double)>[];
  final dstPts = <(double, double)>[];
  bestForTarget.forEach((ti, e) {
    srcPts.add((source[e.$1].x, source[e.$1].y));
    dstPts.add((target[ti].x, target[ti].y));
  });
  final finalModel = fitSimilarity(srcPts, dstPts);
  if (finalModel == null) throw AlignException(AlignFailure.noMatch);

  var sumSq = 0.0;
  for (var i = 0; i < srcPts.length; i++) {
    final p = finalModel.apply(srcPts[i].$1, srcPts[i].$2);
    final dx = p.$1 - dstPts[i].$1;
    final dy = p.$2 - dstPts[i].$2;
    sumSq += dx * dx + dy * dy;
  }
  final rms = math.sqrt(sumSq / srcPts.length);

  final s = finalModel.scale;
  if (s < kMinScale || s > kMaxScale || finalModel.rotationDegrees.abs() > kMaxRotationDegrees) {
    throw AlignException(AlignFailure.noMatch);
  }
  // Three pairs is enough to *solve* a similarity but not enough to trust
  // one; that is a different problem from a loose fit, and the advice the
  // user needs is different too, so it gets its own reason.
  if (srcPts.length < 4) throw AlignException(AlignFailure.tooFewMatches);
  if (rms > kPixelTolerance * 1.5) {
    throw AlignException(AlignFailure.highResidual);
  }

  return AlignResult(
    transform: finalModel,
    matchedStars: srcPts.length,
    rmsPixels: rms,
  );
}

Similarity? _fitFromMatches(List<Star> source, List<Star> target, List<List<int>> matches) {
  final s = <(double, double)>[];
  final t = <(double, double)>[];
  for (final m in matches) {
    for (var k = 0; k < 6; k += 2) {
      s.add((source[m[k]].x, source[m[k]].y));
      t.add((target[m[k + 1]].x, target[m[k + 1]].y));
    }
  }
  return fitSimilarity(s, t);
}

/// Worst per-vertex reprojection error of one candidate triangle pair.
double _triangleError(List<Star> source, List<Star> target, List<int> m, Similarity model) {
  var worst = 0.0;
  for (var k = 0; k < 6; k += 2) {
    final p = model.apply(source[m[k]].x, source[m[k]].y);
    final dx = p.$1 - target[m[k + 1]].x;
    final dy = p.$2 - target[m[k + 1]].y;
    final e = math.sqrt(dx * dx + dy * dy);
    if (e > worst) worst = e;
  }
  return worst;
}
