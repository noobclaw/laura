import 'dart:math' as math;

/// How the user expressed the target size for the resize tool.
enum ResizeMode {
  /// Explicit width and/or height in pixels. A missing side follows the
  /// aspect ratio; both given + `keepAspect` = fit inside the box.
  pixels,

  /// Scale factor in percent of the original (1..400).
  percent,

  /// Longest side capped to N pixels; never upscales unless `allowUpscale`.
  longestSide,
}

/// Immutable resize request. Pure data so it can cross isolate boundaries
/// and be unit-tested without Flutter.
class ResizeSpec {
  const ResizeSpec({
    required this.mode,
    this.width,
    this.height,
    this.percent = 100,
    this.longest = 1920,
    this.keepAspect = true,
    this.allowUpscale = false,
  });

  final ResizeMode mode;
  final int? width;
  final int? height;
  final int percent;
  final int longest;
  final bool keepAspect;
  final bool allowUpscale;

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'width': width,
        'height': height,
        'percent': percent,
        'longest': longest,
        'keepAspect': keepAspect,
        'allowUpscale': allowUpscale,
      };

  static ResizeSpec fromJson(Map<String, dynamic> j) => ResizeSpec(
        mode: ResizeMode.values.firstWhere((m) => m.name == j['mode'],
            orElse: () => ResizeMode.longestSide),
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
        percent: (j['percent'] as num?)?.toInt() ?? 100,
        longest: (j['longest'] as num?)?.toInt() ?? 1920,
        keepAspect: j['keepAspect'] as bool? ?? true,
        allowUpscale: j['allowUpscale'] as bool? ?? false,
      );
}

/// Output dimensions for [spec] applied to a `srcW`×`srcH` image.
///
/// Rules (mirroring the reference implementation's ImageScaler semantics):
/// - never returns a side smaller than 1;
/// - rounding is to nearest, so 4000×3000 → 33% gives 1320×990, not 1319;
/// - when both sides are given with `keepAspect`, the image is fitted inside
///   the box (max scale that keeps both sides ≤ target);
/// - `allowUpscale=false` clamps the scale to 1.0 for percent/longest/single
///   side; explicit both-sides-without-aspect is always honoured verbatim.
({int width, int height}) computeResize(int srcW, int srcH, ResizeSpec spec) {
  if (srcW <= 0 || srcH <= 0) return (width: 1, height: 1);
  switch (spec.mode) {
    case ResizeMode.percent:
      final f = (spec.percent.clamp(1, 400)) / 100.0;
      final s = spec.allowUpscale ? f : math.min(f, 1.0);
      return _scaled(srcW, srcH, s);
    case ResizeMode.longestSide:
      final longest = math.max(1, spec.longest);
      final srcLongest = math.max(srcW, srcH);
      var s = longest / srcLongest;
      if (!spec.allowUpscale) s = math.min(s, 1.0);
      return _scaled(srcW, srcH, s);
    case ResizeMode.pixels:
      final w = spec.width;
      final h = spec.height;
      if (w == null && h == null) return (width: srcW, height: srcH);
      if (!spec.keepAspect && w != null && h != null) {
        return (width: math.max(1, w), height: math.max(1, h));
      }
      double s;
      if (w != null && h != null) {
        s = math.min(w / srcW, h / srcH);
      } else if (w != null) {
        s = w / srcW;
      } else {
        s = h! / srcH;
      }
      if (!spec.allowUpscale) s = math.min(s, 1.0);
      return _scaled(srcW, srcH, s);
  }
}

({int width, int height}) _scaled(int w, int h, double s) => (
      width: math.max(1, (w * s).round()),
      height: math.max(1, (h * s).round()),
    );

/// Human-readable byte count, e.g. `1.2 MB`, `480 KB`, `12 B`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(mb < 10 ? 2 : 1)} MB';
}
