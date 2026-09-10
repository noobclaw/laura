import 'dart:math' as math;
import 'dart:typed_data';

/// The tone curve applied to a finished stack.
///
/// A stacked night sky lives in the bottom few percent of the range: the
/// interesting signal is a handful of levels above a bright-ish sky glow.
/// Three controls, in the order they are applied:
///
///  * [black] — where the sky background is cut, as a fraction of full scale;
///  * [midtone] — where that background is *placed* afterwards (the classic
///    midtones-transfer-function target), which is what "brightness" means
///    for this kind of image;
///  * [saturation] — colour is what survives least in a stack, so it gets its
///    own control rather than being baked in.
class StretchParams {
  const StretchParams({
    required this.black,
    required this.midtone,
    required this.saturation,
  });

  static const StretchParams neutral =
      StretchParams(black: 0, midtone: 0.5, saturation: 1);

  /// 0…0.9 of full scale.
  final double black;

  /// Target level for the sky background, 0.03…0.6.
  final double midtone;

  /// 0…2, 1 = unchanged.
  final double saturation;

  StretchParams copyWith({double? black, double? midtone, double? saturation}) =>
      StretchParams(
        black: black ?? this.black,
        midtone: midtone ?? this.midtone,
        saturation: saturation ?? this.saturation,
      );

  Map<String, dynamic> toJson() =>
      {'black': black, 'midtone': midtone, 'saturation': saturation};

  static StretchParams fromJson(Map<String, dynamic> j) => StretchParams(
        black: ((j['black'] as num?)?.toDouble() ?? 0).clamp(0.0, 0.9),
        midtone: ((j['midtone'] as num?)?.toDouble() ?? 0.5).clamp(0.03, 0.6),
        saturation: ((j['saturation'] as num?)?.toDouble() ?? 1).clamp(0.0, 2.0),
      );
}

/// Midtones transfer function: maps 0→0, 1→1 and `m`→0.5, with a smooth
/// curve in between. `m = 0.5` is the identity.
double mtf(double m, double x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  final den = (2 * m - 1) * x - m;
  if (den == 0) return x;
  return ((m - 1) * x) / den;
}

/// The `m` that sends [level] to [target] under [mtf]. Inverted from the
/// definition above; clamped away from the ends where the curve degenerates.
double midtoneFor(double level, double target) {
  final x = level.clamp(1e-4, 0.9999);
  final y = target.clamp(1e-3, 0.999);
  final den = 2 * x * y - y - x;
  if (den.abs() < 1e-9) return 0.5;
  return (x * (y - 1) / den).clamp(0.005, 0.95);
}

/// A 256-entry lookup table for the black point + midtone curve, so the
/// per-pixel work is one array read instead of a division.
///
/// [skyLevel] is the measured background of *this* stack (0…1). Anchoring
/// the curve on it is what makes the brightness slider mean the same thing
/// on a dark rural sky and a light-polluted suburban one: the slider says
/// where the sky should end up, not how much gamma to add.
Uint8List toneLut(StretchParams p, double skyLevel) {
  final black = p.black.clamp(0.0, 0.9);
  final span = 1 - black;
  final rel = ((skyLevel - black) / span).clamp(0.001, 0.95);
  final m = midtoneFor(rel, p.midtone.clamp(0.03, 0.6));
  final lut = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    final x = ((i / 255) - black) / span;
    final y = mtf(m, x.clamp(0.0, 1.0));
    lut[i] = (y * 255).round().clamp(0, 255);
  }
  return lut;
}

/// Sky background level (0…1) of a stacked image, read off a luminance
/// histogram: the 50th percentile of a night frame *is* the sky.
double skyLevelFromHistogram(Int32List hist) {
  var total = 0;
  for (final c in hist) {
    total += c;
  }
  if (total == 0) return 0.1;
  final half = total ~/ 2;
  var run = 0;
  for (var i = 0; i < hist.length; i++) {
    run += hist[i];
    if (run >= half) return i / (hist.length - 1);
  }
  return 0.1;
}

/// Black point (0…1) for a stack: the level below which only [fraction] of
/// the pixels sit. Cutting there removes the deepest part of the sky glow
/// without clipping structure.
double blackPointFromHistogram(Int32List hist, {double fraction = 0.005}) {
  var total = 0;
  for (final c in hist) {
    total += c;
  }
  if (total == 0) return 0;
  final want = (total * fraction).floor();
  var run = 0;
  for (var i = 0; i < hist.length; i++) {
    run += hist[i];
    if (run >= want) return i / (hist.length - 1);
  }
  return 0;
}

/// Luminance histogram (256 bins) of a packed RGB buffer, sampled on a
/// stride so a 12 MP stack costs a few milliseconds.
Int32List lumaHistogram(Uint8List rgb, {int maxSamples = 200000}) {
  final pixels = rgb.length ~/ 3;
  final stride = math.max(1, pixels ~/ maxSamples);
  final hist = Int32List(256);
  for (var p = 0; p < pixels; p += stride) {
    final i = p * 3;
    hist[(77 * rgb[i] + 150 * rgb[i + 1] + 29 * rgb[i + 2]) >> 8]++;
  }
  return hist;
}

/// What the tone controls need to know about one finished stack.
class ToneStats {
  const ToneStats({required this.autoBlack, required this.skyLevel});

  /// Suggested black point (0…1).
  final double autoBlack;

  /// Measured sky background (median luminance, 0…1).
  final double skyLevel;

  Map<String, dynamic> toJson() => {'autoBlack': autoBlack, 'skyLevel': skyLevel};

  static ToneStats fromJson(Map<String, dynamic> j) => ToneStats(
        autoBlack: (j['autoBlack'] as num?)?.toDouble() ?? 0,
        skyLevel: (j['skyLevel'] as num?)?.toDouble() ?? 0.1,
      );
}

ToneStats measureTone(Uint8List rgb) {
  final hist = lumaHistogram(rgb);
  return ToneStats(
    autoBlack: blackPointFromHistogram(hist),
    skyLevel: skyLevelFromHistogram(hist),
  );
}

/// Sensible starting point for a freshly stacked image: cut just under the
/// sky, then lift the sky to a quarter of the range.
StretchParams autoStretch(ToneStats stats) => StretchParams(
      black: stats.autoBlack,
      midtone: 0.25,
      saturation: 1.15,
    );

/// Apply [p] to a packed RGB buffer, writing into [dest] (may be [src]).
///
/// Saturation is applied around the pixel's own luminance so a colour cast in
/// the sky is amplified no more than the stars are.
void applyStretch(Uint8List src, Uint8List dest, StretchParams p, double skyLevel) {
  final lut = toneLut(p, skyLevel);
  final sat = p.saturation.clamp(0.0, 2.0);
  final plain = (sat - 1).abs() < 0.001;
  for (var i = 0; i < src.length; i += 3) {
    final r = lut[src[i]];
    final g = lut[src[i + 1]];
    final b = lut[src[i + 2]];
    if (plain) {
      dest[i] = r;
      dest[i + 1] = g;
      dest[i + 2] = b;
      continue;
    }
    final y = (77 * r + 150 * g + 29 * b) >> 8;
    dest[i] = _clamp8(y + (r - y) * sat);
    dest[i + 1] = _clamp8(y + (g - y) * sat);
    dest[i + 2] = _clamp8(y + (b - y) * sat);
  }
}

int _clamp8(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());
