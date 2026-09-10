import 'dart:math' as math;
import 'dart:typed_data';

/// One detected point source: sub-pixel centroid plus its integrated flux
/// above the background.
class Star {
  const Star(this.x, this.y, this.flux, this.area);
  final double x;
  final double y;
  final double flux;
  final int area;
}

/// Everything the detector learned about one frame.
class StarField {
  const StarField({
    required this.stars,
    required this.background,
    required this.noise,
    required this.blobs,
    required this.overloaded,
  });

  /// Brightest first, capped at [kMaxControlPoints].
  final List<Star> stars;
  final double background;
  final double noise;

  /// Connected components that passed the area filter (before the cap).
  final int blobs;

  /// True when even the raised threshold left more runs than we will process
  /// — a daylight/indoor picture, or a frame with a huge bright subject.
  final bool overloaded;
}

/// The number of brightest sources used as control points. More points make
/// the invariant space denser without adding information: the faint tail is
/// exactly where centroids are least stable.
const int kMaxControlPoints = 50;

/// Minimum connected pixels for a detection. Hot pixels and read noise are
/// 1–2 px; a real star on a phone sensor spans several.
const int kMinStarArea = 5;

/// Maximum connected pixels. Above this it is the moon, a lamp, a cloud edge
/// or the horizon — none of which is a usable control point.
const int kMaxStarArea = 4000;

/// Runs above threshold we are willing to process before deciding the frame
/// is not a star field. 400k runs already means a quarter of the rows are
/// mostly bright.
const int _kMaxRuns = 400000;

/// Convert an RGB byte buffer to luminance. ITU-R BT.601 weights in integer
/// form so the whole pass stays in the integer unit.
Uint8List rgbToLuma(Uint8List rgb, int w, int h) {
  final n = w * h;
  final out = Uint8List(n);
  var s = 0;
  for (var i = 0; i < n; i++) {
    out[i] = (77 * rgb[s] + 150 * rgb[s + 1] + 29 * rgb[s + 2]) >> 8;
    s += 3;
  }
  return out;
}

/// Robust background level and noise, from a strided sample of [luma].
///
/// Three rounds of 3-sigma clipping on a 256-bin histogram: stars are a
/// bright minority, so clipping the top tail converges on the sky level.
/// The noise floor is clamped at 1.0 so a synthetic or heavily denoised
/// frame cannot drive the detection threshold onto the background itself.
({double background, double noise}) estimateBackground(Uint8List luma) {
  final stride = math.max(1, (luma.length / 40000).floor());
  final hist = Int32List(256);
  for (var i = 0; i < luma.length; i += stride) {
    hist[luma[i]]++;
  }
  var lo = 0;
  var hi = 255;
  var mean = 0.0;
  var sd = 0.0;
  for (var iter = 0; iter < 3; iter++) {
    var n = 0;
    var sum = 0.0;
    for (var v = lo; v <= hi; v++) {
      n += hist[v];
      sum += v * hist[v];
    }
    if (n == 0) break;
    mean = sum / n;
    var ss = 0.0;
    for (var v = lo; v <= hi; v++) {
      final d = v - mean;
      ss += d * d * hist[v];
    }
    sd = math.sqrt(ss / n);
    final nlo = math.max(0, (mean - 3 * sd).floor());
    final nhi = math.min(255, (mean + 3 * sd).ceil());
    if (nlo == lo && nhi == hi) break;
    lo = nlo;
    hi = nhi;
  }
  return (background: mean, noise: math.max(sd, 1.0));
}

/// Detect point sources in a luminance plane.
///
/// Run-length connected components: each row contributes maximal runs of
/// pixels above the threshold, and runs are merged with the previous row's
/// through a union-find. Memory is proportional to the number of bright runs,
/// not to the pixel count — a full-resolution 12 MP frame never allocates the
/// 48 MB label array a pixel-wise labelling would need.
///
/// [sigmaFactor] is the detection threshold in units of background noise.
StarField detectStars(
  Uint8List luma,
  int width,
  int height, {
  double sigmaFactor = 5,
  int minArea = kMinStarArea,
  int maxArea = kMaxStarArea,
  int maxStars = kMaxControlPoints,
}) {
  final bg = estimateBackground(luma);
  var field = _extract(luma, width, height, bg.background,
      bg.background + sigmaFactor * bg.noise, minArea, maxArea, maxStars);
  // Too many bright runs at 5σ. One retry at 8σ before giving up, which
  // rescues a frame with light pollution or a bright foreground.
  field ??= _extract(luma, width, height, bg.background,
      bg.background + 8 * bg.noise, minArea, maxArea, maxStars);
  if (field == null) {
    return StarField(
        stars: const [],
        background: bg.background,
        noise: bg.noise,
        blobs: 0,
        overloaded: true);
  }
  return StarField(
    stars: field.stars,
    background: bg.background,
    noise: bg.noise,
    blobs: field.blobs,
    overloaded: false,
  );
}

({List<Star> stars, int blobs})? _extract(
  Uint8List luma,
  int width,
  int height,
  double background,
  double threshold,
  int minArea,
  int maxArea,
  int maxStars,
) {
  final t = threshold.clamp(1.0, 254.0);
  final ti = t.floor();

  // Per-run state, grown as runs are found.
  final x0s = <int>[];
  final x1s = <int>[];
  final parent = <int>[];
  final areas = <int>[];
  final fluxes = <double>[];
  final fxs = <double>[];
  final fys = <double>[];

  int find(int i) {
    var r = i;
    while (parent[r] != r) {
      r = parent[r];
    }
    // Path compression, so later finds on a long chain stay cheap.
    var c = i;
    while (parent[c] != r) {
      final next = parent[c];
      parent[c] = r;
      c = next;
    }
    return r;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[rb < ra ? ra : rb] = rb < ra ? rb : ra;
  }

  var prevStart = 0;
  var prevEnd = 0; // [prevStart, prevEnd) are the previous row's runs
  for (var y = 0; y < height; y++) {
    final rowStart = x0s.length;
    final base = y * width;
    var x = 0;
    while (x < width) {
      if (luma[base + x] <= ti) {
        x++;
        continue;
      }
      final start = x;
      var area = 0;
      var flux = 0.0;
      var fx = 0.0;
      var fy = 0.0;
      while (x < width && luma[base + x] > ti) {
        final w = luma[base + x] - background;
        area++;
        flux += w;
        fx += w * x;
        fy += w * y;
        x++;
      }
      final idx = x0s.length;
      if (idx >= _kMaxRuns) return null;
      x0s.add(start);
      x1s.add(x - 1);
      parent.add(idx);
      areas.add(area);
      fluxes.add(flux);
      fxs.add(fx);
      fys.add(fy);

      // 8-connectivity: touching or diagonally adjacent columns count.
      for (var p = prevStart; p < prevEnd; p++) {
        if (x1s[p] >= start - 1 && x0s[p] <= x - 1 + 1) union(p, idx);
      }
    }
    prevStart = rowStart;
    prevEnd = x0s.length;
  }

  // Fold each run into its component root.
  final blobArea = <int, int>{};
  final blobFlux = <int, double>{};
  final blobFx = <int, double>{};
  final blobFy = <int, double>{};
  for (var i = 0; i < x0s.length; i++) {
    final r = find(i);
    blobArea[r] = (blobArea[r] ?? 0) + areas[i];
    blobFlux[r] = (blobFlux[r] ?? 0) + fluxes[i];
    blobFx[r] = (blobFx[r] ?? 0) + fxs[i];
    blobFy[r] = (blobFy[r] ?? 0) + fys[i];
  }

  final stars = <Star>[];
  blobArea.forEach((root, area) {
    if (area < minArea || area > maxArea) return;
    final flux = blobFlux[root]!;
    if (flux <= 0) return;
    stars.add(Star(blobFx[root]! / flux, blobFy[root]! / flux, flux, area));
  });
  final blobs = stars.length;
  stars.sort((a, b) => b.flux.compareTo(a.flux));
  return (
    stars: stars.length > maxStars ? stars.sublist(0, maxStars) : stars,
    blobs: blobs,
  );
}
