import 'dart:math' as math;
import 'dart:typed_data';

import 'stars.dart';

/// Star-shape statistics of one frame: how fat and how round its stars are.
///
/// Spec taken from astra_lite `src/image/stars.rs` (MIT, © art-den):
/// `calc_common_star_image` builds one "average star" by median-combining
/// magnified cut-outs of the frame's stars, then `calc_hfd` / `calc_fwhm` /
/// `calc_ovality` measure that one image. Written from the spec in Dart; the
/// constants are the reference project's. What it is for here: a frame whose
/// stars are twice as fat as the reference's is defocused or motion-blurred
/// and would only smear the stack (astra_lite's `FrameQuality.fwhm_is_ok`).
class StarShape {
  const StarShape({
    required this.fwhm,
    required this.hfd,
    required this.ovality,
    required this.sampled,
  });

  /// Full width at half maximum of the average star, in source pixels.
  /// 0 when nothing could be measured.
  final double fwhm;

  /// Half-flux diameter, in source pixels. Less sensitive to the half-max
  /// threshold than [fwhm]; reported for the curious, not gated on.
  final double hfd;

  /// Difference between the widest and the perpendicular diameter of the
  /// average star, in source pixels. 0 for a round star; a trailed frame
  /// (the phone moved during the exposure) shows up here.
  final double ovality;

  /// How many stars went into the average.
  final int sampled;

  static const StarShape none = StarShape(fwhm: 0, hfd: 0, ovality: 0, sampled: 0);

  bool get measured => sampled > 0 && fwhm > 0;
}

/// Magnification of the common star image (astra_lite `COMMON_STAR_MAG`).
const int kShapeMagnification = 4;

/// astra_lite `MAX_STARS_CNT_FOR_STAR_IMAGE` / `MIN_STARS_CNT_FOR_STAR_IMAGE`.
const int kMaxShapeStars = 100;
const int kMinShapeStars = 50;

/// astra_lite `MAX_STAR_DIAM`: cut-outs never exceed this many source pixels.
const int kMaxStarDiameter = 32;

/// Directions probed for the ovality (astra_lite `ANGLE_CNT`).
const int kOvalityAngles = 32;

/// A frame whose FWHM exceeds this multiple of the reference frame's is
/// rejected as [AlignFailure.blurry]. astra_lite gates on a user-set absolute
/// FWHM (default 5 px, off by default); a phone app has no such setting and
/// pixel scales differ per lens, so the gate is relative to the reference.
const double kBlurFwhmRatio = 2.0;

/// 8-bit luma at or above this is treated as saturated (astra_lite skips
/// `overexposed` stars, detected there from a plateau at the peak).
const int kSaturatedLuma = 250;

/// True when [fwhm] says the frame is too blurred to add to a stack whose
/// reference measures [referenceFwhm]. Unmeasurable values never reject.
bool isBlurry(double fwhm, double referenceFwhm) =>
    referenceFwhm > 0 && fwhm > 0 && fwhm > kBlurFwhmRatio * referenceFwhm;

/// Measure the average star of one frame. [stars] are the detector's control
/// points (brightest first); [background] the frame's sky level.
StarShape measureStarShape(
  Uint8List luma,
  int width,
  int height,
  List<Star> stars,
  double background,
) {
  if (stars.isEmpty || width < 3 || height < 3) return StarShape.none;

  // (star, peak − background) for the usable stars: not saturated, above sky.
  final usable = <(Star, double)>[];
  for (final s in stars) {
    final peak = _peakAround(luma, width, height, s);
    if (peak >= kSaturatedLuma) continue;
    final range = peak - background;
    if (range <= 0) continue;
    usable.add((s, range));
  }
  if (usable.isEmpty) return StarShape.none;

  // Prefer stars near the centre of the frame, widening the ring until
  // enough are in (astra_lite: 0.5 / 0.66 / 0.75 / 1.0 × half the short
  // side, then everything).
  final imgSize = math.min(width, height) / 2;
  final cx = width ~/ 2;
  final cy = height ~/ 2;
  final rings = [0.5 * imgSize, 0.66 * imgSize, 0.75 * imgSize, imgSize, 1e6];
  var picked = <(Star, double)>[];
  for (final ring in rings) {
    picked = [];
    for (final e in usable) {
      final dx = e.$1.x - cx;
      final dy = e.$1.y - cy;
      if (math.sqrt(dx * dx + dy * dy) < ring) picked.add(e);
      if (picked.length > kMaxShapeStars) break;
    }
    if (picked.length > kMinShapeStars) break;
  }
  if (picked.isEmpty) return StarShape.none;

  // Cut-out size: three times the average star's half-extent, magnified.
  // astra_lite keeps a per-star bounding box; the run-length detector only
  // keeps the area, so the half-extent is the equivalent-disc radius.
  var sumWidth = 0.0;
  for (final e in picked) {
    final radius = math.sqrt(e.$1.area / math.pi);
    sumWidth += 3 * (radius + 1);
  }
  final avgWidth = (sumWidth / picked.length).round().clamp(5, kMaxStarDiameter);
  const k = kShapeMagnification;
  var size = avgWidth * k;
  if (size.isEven) size += 1;
  final half = size ~/ 2;

  // The common star image: per output pixel, the median over stars of the
  // background-subtracted, peak-normalised sample at the same offset.
  final common = Float64List(size * size);
  final values = Float64List(picked.length);
  const kf = 1.0 / k;
  for (var y = 0; y < size; y++) {
    final yf = kf * (y - half);
    for (var x = 0; x < size; x++) {
      final xf = kf * (x - half);
      var n = 0;
      for (final e in picked) {
        final v = _sample(luma, width, height, e.$1.x + xf, e.$1.y + yf);
        if (v == null) continue;
        values[n++] = 65535 * (v - background) / e.$2;
      }
      if (n == 0) continue;
      final m = _medianOf(values, n).clamp(0.0, 65535.0);
      common[y * size + x] = m;
    }
  }

  return StarShape(
    fwhm: _fwhm(common, size, k),
    hfd: _hfd(common, size, k),
    ovality: _ovality(common, size, k),
    sampled: picked.length,
  );
}

/// astra_lite `calc_fwhm`: the area at or above half maximum, as the
/// diameter of the disc with that area, in source pixels.
double _fwhm(Float64List img, int size, int k) {
  var area = 0;
  for (final v in img) {
    if (v >= 32767) area++;
  }
  if (area == 0) return 0;
  return 2 * math.sqrt(area / math.pi) / k;
}

/// astra_lite `calc_hfd`: twice the flux-weighted mean distance to the
/// flux centroid, in source pixels.
double _hfd(Float64List img, int size, int k) {
  var sum = 0.0, sx = 0.0, sy = 0.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final v = img[y * size + x];
      sum += v;
      sx += x * v;
      sy += y * v;
    }
  }
  if (sum == 0) return 0;
  final cx = sx / sum;
  final cy = sy / sum;
  var sumD = 0.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = cx - x;
      final dy = cy - y;
      sumD += math.sqrt(dx * dx + dy * dy) * img[y * size + x];
    }
  }
  return 2 * (sumD / sum) / k;
}

/// astra_lite `calc_ovality`: the half-max width along [kOvalityAngles]
/// directions through the centre; the widest minus the one perpendicular
/// to it, in source pixels.
double _ovality(Float64List img, int size, int k) {
  final c = (size ~/ 2).toDouble();
  final widths = List<int>.filled(kOvalityAngles, 0);
  for (var i = 0; i < kOvalityAngles; i++) {
    final angle = math.pi * i / kOvalityAngles;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    int? first;
    int? last;
    var prevOver = false;
    for (var j = -(size ~/ 2); j < size ~/ 2; j++) {
      final v = _sampleF(img, size, j * cosA + c, j * sinA + c);
      final over = v != null && v >= 32767;
      if (first == null && over) first = j;
      if (prevOver && !over) last = j - 1;
      prevOver = over;
    }
    widths[i] = (first != null && last != null) ? last - first + 1 : 0;
  }
  var maxPos = 0;
  for (var i = 1; i < kOvalityAngles; i++) {
    if (widths[i] > widths[maxPos]) maxPos = i;
  }
  final minPos = (maxPos + kOvalityAngles ~/ 2) % kOvalityAngles;
  return (widths[maxPos] - widths[minPos]) / k;
}

/// Brightest luma within one pixel of the centroid.
int _peakAround(Uint8List luma, int w, int h, Star s) {
  final x0 = s.x.round();
  final y0 = s.y.round();
  var peak = 0;
  for (var dy = -1; dy <= 1; dy++) {
    final y = y0 + dy;
    if (y < 0 || y >= h) continue;
    for (var dx = -1; dx <= 1; dx++) {
      final x = x0 + dx;
      if (x < 0 || x >= w) continue;
      final v = luma[y * w + x];
      if (v > peak) peak = v;
    }
  }
  return peak;
}

/// Bilinear sample of a luma plane; null outside the frame.
double? _sample(Uint8List luma, int w, int h, double x, double y) {
  if (x < 0 || y < 0 || x > w - 1 || y > h - 1) return null;
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = x0 < w - 1 ? x0 + 1 : x0;
  final y1 = y0 < h - 1 ? y0 + 1 : y0;
  final fx = x - x0;
  final fy = y - y0;
  final a = luma[y0 * w + x0] * (1 - fx) + luma[y0 * w + x1] * fx;
  final b = luma[y1 * w + x0] * (1 - fx) + luma[y1 * w + x1] * fx;
  return a * (1 - fy) + b * fy;
}

double? _sampleF(Float64List img, int size, double x, double y) {
  if (x < 0 || y < 0 || x > size - 1 || y > size - 1) return null;
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = x0 < size - 1 ? x0 + 1 : x0;
  final y1 = y0 < size - 1 ? y0 + 1 : y0;
  final fx = x - x0;
  final fy = y - y0;
  final a = img[y0 * size + x0] * (1 - fx) + img[y0 * size + x1] * fx;
  final b = img[y1 * size + x0] * (1 - fx) + img[y1 * size + x1] * fx;
  return a * (1 - fy) + b * fy;
}

/// Median of the first [n] entries (upper median for even [n], matching
/// `select_nth_unstable(len / 2)`). Sorts in place; the buffer is scratch.
double _medianOf(Float64List v, int n) {
  for (var i = 1; i < n; i++) {
    final key = v[i];
    var j = i - 1;
    while (j >= 0 && v[j] > key) {
      v[j + 1] = v[j];
      j--;
    }
    v[j + 1] = key;
  }
  return v[n ~/ 2];
}
