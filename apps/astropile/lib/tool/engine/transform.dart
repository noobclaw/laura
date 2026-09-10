import 'dart:math' as math;

/// A 2D similarity transform (uniform scale + rotation + translation):
///
///     u = c·x − d·y + tx
///     v = d·x + c·y + ty
///
/// with `c = s·cosθ` and `d = s·sinθ`. Four degrees of freedom, which is
/// exactly what separates two frames of the same sky taken seconds apart:
/// the phone shifted and rolled a little. An affine or homography fit has
/// more freedom than the data supports and starts bending the field.
class Similarity {
  const Similarity(this.c, this.d, this.tx, this.ty);

  static const Similarity identity = Similarity(1, 0, 0, 0);

  final double c;
  final double d;
  final double tx;
  final double ty;

  bool get isIdentity => c == 1 && d == 0 && tx == 0 && ty == 0;

  double get scale => math.sqrt(c * c + d * d);
  double get rotationDegrees => math.atan2(d, c) * 180 / math.pi;

  /// Distance the transform moves the origin, in pixels.
  double get shiftPixels => math.sqrt(tx * tx + ty * ty);

  (double, double) apply(double x, double y) =>
      (c * x - d * y + tx, d * x + c * y + ty);

  /// Target → source. Used by both the resampler and the stacker (the
  /// stacker asks "did this frame actually cover this output pixel?").
  (double, double) inverse(double u, double v) {
    final k = c * c + d * d;
    if (k == 0) return (0, 0);
    final pu = u - tx;
    final pv = v - ty;
    return ((c * pu + d * pv) / k, (-d * pu + c * pv) / k);
  }

  Map<String, dynamic> toJson() => {'c': c, 'd': d, 'tx': tx, 'ty': ty};

  static Similarity fromJson(Map<String, dynamic> j) => Similarity(
        (j['c'] as num?)?.toDouble() ?? 1,
        (j['d'] as num?)?.toDouble() ?? 0,
        (j['tx'] as num?)?.toDouble() ?? 0,
        (j['ty'] as num?)?.toDouble() ?? 0,
      );

  @override
  String toString() =>
      'Similarity(scale ${scale.toStringAsFixed(4)}, rot '
      '${rotationDegrees.toStringAsFixed(2)}°, t ${tx.toStringAsFixed(1)}, '
      '${ty.toStringAsFixed(1)})';
}

/// Least-squares similarity mapping [source] onto [target], in closed form.
///
/// Both lists must be the same length and hold corresponding points. With
/// centred coordinates the normal equations separate and give
///
///     c = Σ(x'·u' + y'·v') / Σ(x'² + y'²)
///     d = Σ(x'·v' − y'·u') / Σ(x'² + y'²)
///
/// Returns null when the source points are degenerate (all coincident), which
/// is the only case that makes the denominator vanish.
Similarity? fitSimilarity(List<(double, double)> source, List<(double, double)> target) {
  final n = source.length;
  if (n < 2 || target.length != n) return null;
  var sx = 0.0, sy = 0.0, tu = 0.0, tv = 0.0;
  for (var i = 0; i < n; i++) {
    sx += source[i].$1;
    sy += source[i].$2;
    tu += target[i].$1;
    tv += target[i].$2;
  }
  sx /= n;
  sy /= n;
  tu /= n;
  tv /= n;
  var num1 = 0.0, num2 = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    final x = source[i].$1 - sx;
    final y = source[i].$2 - sy;
    final u = target[i].$1 - tu;
    final v = target[i].$2 - tv;
    num1 += x * u + y * v;
    num2 += x * v - y * u;
    den += x * x + y * y;
  }
  if (den <= 1e-9) return null;
  final c = num1 / den;
  final d = num2 / den;
  return Similarity(c, d, tu - (c * sx - d * sy), tv - (d * sx + c * sy));
}
