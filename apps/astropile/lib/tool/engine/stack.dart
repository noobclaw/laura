import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'transform.dart';

/// How the aligned frames are combined.
enum StackMode {
  /// Average of every frame that covered the pixel. Best signal-to-noise for
  /// a given number of frames.
  mean,

  /// Middle value. Throws away anything that appears in a minority of frames
  /// — aircraft, satellites, hot pixels, a passing cloud edge — at the cost
  /// of roughly a fifth of the noise reduction mean would have given. Pro.
  median,

  /// Mean of the values that survive [kKappa]-sigma rejection, repeated up to
  /// [kKappaIterations] times. Keeps most of mean's noise reduction while
  /// still dropping outliers, which median pays a fifth of the signal for.
  /// Pro. Spec from DeepSkyStacker (BSD-3) — see REFERENCE.md §E.
  kappaSigma,

  /// Brightest value. Combined *without* star alignment, this is the star
  /// trail mode: the ground stays put and every star draws its arc.
  max,
}

extension StackModeX on StackMode {
  /// True for the mode that must not align on stars — aligning would cancel
  /// exactly the motion the picture is made of.
  bool get isTrails => this == StackMode.max;

  /// The two modes behind the Pro gate. Trails is deliberately free: the
  /// six-frame free cap already limits how long an arc it can draw.
  bool get needsPro => this == StackMode.median || this == StackMode.kappaSigma;
}

/// Rejection width, in standard deviations, for [StackMode.kappaSigma].
/// DeepSkyStacker's shipped default (`Stacking/Light_Kappa`).
const double kKappa = 2.0;

/// Maximum rejection passes. DeepSkyStacker's shipped default
/// (`Stacking/Light_Iteration`); the loop also stops early once a pass
/// rejects nothing.
const int kKappaIterations = 5;

/// One aligned frame on disk: packed RGB in the reference frame's grid, plus
/// the transform that put it there (needed to know which pixels it covered).
class AlignedFrame {
  const AlignedFrame({
    required this.path,
    required this.transform,
    required this.sourceWidth,
    required this.sourceHeight,
  });
  final String path;
  final Similarity transform;
  final int sourceWidth;
  final int sourceHeight;
}

/// Rows combined per work unit. Small enough that peak memory is
/// `band × width × 3 × frames` (≈ 24 MB for 32 frames of a 4000 px wide
/// stack), large enough that per-band seeks stay negligible.
const int kStackBandRows = 48;

/// The half-open range of output columns that [t] covered on output row [v].
///
/// The inverse map is affine, so along a horizontal line each of the four
/// source-bounds constraints is a linear inequality in `u`: the covered set
/// is one interval, computed in constant time per row instead of per pixel.
/// Returns `(0, -1)` when the row is not covered at all.
(int, int) rowCoverage(Similarity t, int srcW, int srcH, int outW, double v) {
  if (t.isIdentity) return (0, outW - 1);
  final k = t.c * t.c + t.d * t.d;
  if (k == 0) return (0, -1);
  final ax = t.c / k;
  final bx = (-t.c * t.tx + t.d * (v - t.ty)) / k;
  final ay = -t.d / k;
  final by = (t.d * t.tx + t.c * (v - t.ty)) / k;

  var lo = 0.0;
  var hi = (outW - 1).toDouble();

  bool clip(double a, double b, double limit) {
    // 0 ≤ a·u + b ≤ limit
    if (a.abs() < 1e-12) return b >= 0 && b <= limit;
    final u1 = (0 - b) / a;
    final u2 = (limit - b) / a;
    final l = u1 < u2 ? u1 : u2;
    final r = u1 < u2 ? u2 : u1;
    if (l > lo) lo = l;
    if (r < hi) hi = r;
    return true;
  }

  if (!clip(ax, bx, (srcW - 1).toDouble())) return (0, -1);
  if (!clip(ay, by, (srcH - 1).toDouble())) return (0, -1);
  final l = lo.ceil();
  final r = hi.floor();
  if (l > r) return (0, -1);
  return (l < 0 ? 0 : l, r > outW - 1 ? outW - 1 : r);
}

/// Combine rows `[y0, y1)` of the output.
///
/// Reads that band from every aligned frame, keeps only the frames that
/// actually covered each pixel, and returns the packed RGB band. Runs inside
/// a background isolate — plain data in, plain data out.
Uint8List stackBand(
  List<AlignedFrame> frames,
  int width,
  int y0,
  int y1,
  StackMode mode,
) {
  final rows = y1 - y0;
  final rowBytes = width * 3;
  final n = frames.length;
  // A short read means the scratch file was truncated (the disk filled up
  // during the align pass). Padding with zeroes and averaging them in would
  // silently darken a band of the picture, so a truncated frame is dropped
  // from this band instead.
  final short = List<bool>.filled(n, false);
  final bands = List<Uint8List>.generate(n, (i) {
    final f = File(frames[i].path).openSync();
    try {
      f.setPositionSync(y0 * rowBytes);
      final got = f.readSync(rows * rowBytes);
      if (got.length == rows * rowBytes) return got;
      short[i] = true;
      final padded = Uint8List(rows * rowBytes);
      padded.setRange(0, got.length, got);
      return padded;
    } finally {
      f.closeSync();
    }
  });

  final out = Uint8List(rows * rowBytes);
  // Int32, not Uint8: these are frame indices, and a Uint8 would wrap round
  // silently the day the frame cap goes above 255.
  final idx = Int32List(n);
  final vals = Uint8List(n);
  // Per-frame covered column range for the row being combined.
  final loOf = Int32List(n);
  final hiOf = Int32List(n);

  for (var r = 0; r < rows; r++) {
    final v = (y0 + r).toDouble();
    for (var i = 0; i < n; i++) {
      if (short[i]) {
        loOf[i] = 0;
        hiOf[i] = -1;
        continue;
      }
      final f = frames[i];
      final range = rowCoverage(f.transform, f.sourceWidth, f.sourceHeight, width, v);
      loOf[i] = range.$1;
      hiOf[i] = range.$2;
    }
    final rowBase = r * rowBytes;
    for (var x = 0; x < width; x++) {
      var count = 0;
      for (var i = 0; i < n; i++) {
        if (x >= loOf[i] && x <= hiOf[i]) idx[count++] = i;
      }
      final o = rowBase + x * 3;
      if (count == 0) continue; // stays black: no frame saw this pixel
      for (var ch = 0; ch < 3; ch++) {
        final at = o + ch;
        switch (mode) {
          case StackMode.mean:
            var sum = 0;
            for (var k = 0; k < count; k++) {
              sum += bands[idx[k]][at];
            }
            out[at] = sum ~/ count;
          case StackMode.max:
            var top = 0;
            for (var k = 0; k < count; k++) {
              final v = bands[idx[k]][at];
              if (v > top) top = v;
            }
            out[at] = top;
          case StackMode.median:
            for (var k = 0; k < count; k++) {
              vals[k] = bands[idx[k]][at];
            }
            out[at] = medianOf(vals, count);
          case StackMode.kappaSigma:
            for (var k = 0; k < count; k++) {
              vals[k] = bands[idx[k]][at];
            }
            out[at] = kappaSigmaClip(vals, count);
        }
      }
    }
  }
  return out;
}

/// Mean of the first [count] entries after kappa-sigma rejection, in place.
///
/// Spec (DeepSkyStacker `KappaSigmaClip`, DSSTools.h:606 — BSD-3, read and
/// re-specified, not copied; REFERENCE.md §E-1):
/// sort, then up to [iterations] passes over the surviving window: take its
/// mean `m` and population sigma `s`, keep only `m − κs ≤ v ≤ m + κs`, stop
/// as soon as a pass rejects nothing. The answer is the mean of what is left.
///
/// **Intentional deviation**: the original ends the loop when the window
/// empties and then averages an empty set (0/0). A pass that would reject
/// *every* value is discarded here and the previous window kept, so the
/// result is always a real number. It can only trigger where the values are
/// so spread that no centre exists — a hot pixel column, say — and returning
/// NaN there would write 0 and punch a black hole in the picture.
int kappaSigmaClip(Uint8List v, int count, {
  double kappa = kKappa,
  int iterations = kKappaIterations,
}) {
  if (count <= 2) {
    var sum = 0;
    for (var i = 0; i < count; i++) {
      sum += v[i];
    }
    return count == 0 ? 0 : (sum / count).round();
  }
  // The window is sorted, so rejection is two moving ends rather than a
  // rebuilt list: everything below the low bound is a prefix, everything
  // above the high bound a suffix.
  medianOf(v, count); // sorts v[0..count) in place
  var lo = 0;
  var hi = count;
  var mean = 0.0;
  for (var pass = 0; pass < iterations; pass++) {
    final n = hi - lo;
    var sum = 0.0;
    for (var i = lo; i < hi; i++) {
      sum += v[i];
    }
    mean = sum / n;
    var sq = 0.0;
    for (var i = lo; i < hi; i++) {
      final d = v[i] - mean;
      sq += d * d;
    }
    final sigma = math.sqrt(sq / n);
    if (sigma <= 0) break; // every survivor is identical
    final min = mean - kappa * sigma;
    final max = mean + kappa * sigma;
    var nlo = lo;
    var nhi = hi;
    while (nlo < nhi && v[nlo] < min) {
      nlo++;
    }
    while (nhi > nlo && v[nhi - 1] > max) {
      nhi--;
    }
    if (nhi <= nlo) break; // would reject everything — keep this window
    if (nlo == lo && nhi == hi) break; // nothing rejected: converged
    lo = nlo;
    hi = nhi;
  }
  var sum = 0.0;
  for (var i = lo; i < hi; i++) {
    sum += v[i];
  }
  mean = sum / (hi - lo);
  final r = mean.round();
  return r < 0 ? 0 : (r > 255 ? 255 : r);
}

/// Median of the first [count] entries, in place, by insertion sort.
/// `count ≤ 32`, where the constant factor beats any general algorithm.
int medianOf(Uint8List v, int count) {
  for (var i = 1; i < count; i++) {
    final key = v[i];
    var j = i - 1;
    while (j >= 0 && v[j] > key) {
      v[j + 1] = v[j];
      j--;
    }
    v[j + 1] = key;
  }
  final mid = count >> 1;
  return count.isOdd ? v[mid] : (v[mid - 1] + v[mid]) >> 1;
}
