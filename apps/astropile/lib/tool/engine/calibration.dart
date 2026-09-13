/// Calibration removes the camera's own fingerprint from every light frame:
///
/// * a **dark** frame is shot with the lens cap on, at the same ISO and
///   shutter as the lights, and holds the sensor's thermal signal and its hot
///   pixels — it is *subtracted*;
/// * a **flat** frame is shot of an evenly lit surface and holds vignetting
///   and dust shadows — the lights are *divided* by it.
///
/// Both are averaged down to one master first, because a single dark frame
/// would add its own read noise back into every light.
///
/// The maths follows DeepSkyStacker (BSD-3): subtraction clamped at zero, and
/// division normalised by the master flat's own per-channel mean so the
/// exposure level does not shift. Specification and the line-by-line
/// comparison live in REFERENCE.md §E.
library;

import 'dart:io';
import 'dart:typed_data';

import 'stack.dart';
import 'transform.dart';

/// How many rows of a master are held in memory at once while calibrating.
/// Peak is `band × width × 3 × 2` (dark + flat) ≈ 6 MB on a 4000 px frame —
/// the masters themselves are never loaded whole, which is what keeps a
/// calibrated run inside the same memory envelope as an uncalibrated one.
const int kCalibrationBandRows = 128;

/// The smallest usable master flat level. A flat whose channel mean is at or
/// below this is either a lens-cap shot by mistake or hopelessly underexposed;
/// dividing by it would multiply the lights into white.
const double kMinFlatMean = 8.0;

/// A built pair of masters, ready to apply to every light frame.
class MasterFrames {
  const MasterFrames({
    required this.width,
    required this.height,
    this.darkPath,
    this.flatPath,
    this.flatMeans = const [0, 0, 0],
    this.darkFrames = 0,
    this.flatFrames = 0,
  });

  /// Nothing to apply — the run is uncalibrated.
  static const MasterFrames none = MasterFrames(width: 0, height: 0);

  final int width;
  final int height;

  /// Packed RGB master dark, or null.
  final String? darkPath;

  /// Packed RGB master flat, or null.
  final String? flatPath;

  /// Per-channel mean of the master flat; the divisor's numerator.
  final List<double> flatMeans;

  final int darkFrames;
  final int flatFrames;

  bool get isEmpty => darkPath == null && flatPath == null;
  bool get isNotEmpty => !isEmpty;
}

/// Raised when a master cannot be used — the caller turns it into a sentence
/// naming which master and why, rather than a silent uncalibrated run.
class CalibrationException implements Exception {
  CalibrationException(this.kind, this.reason);

  /// `dark` or `flat`.
  final CalibrationKind kind;
  final CalibrationProblem reason;

  @override
  String toString() => 'CalibrationException($kind, $reason)';
}

enum CalibrationKind { dark, flat }

enum CalibrationProblem {
  /// The master's pixel size does not match the light frames.
  sizeMismatch,

  /// The scratch file is missing or shorter than `w × h × 3`.
  truncated,

  /// The master flat is (near) black, so dividing by it is meaningless.
  flatTooDark,
}

/// Combine already-decoded calibration raws into one master, per-pixel median.
///
/// Median rather than mean: a satellite, a light leak or a stray reflection in
/// one calibration frame would otherwise be baked into every light frame of
/// the stack. Streams band by band, so peak memory is
/// `band × width × 3 × frames`, not the whole set.
void buildMasterRaw(
  List<String> rawPaths,
  int width,
  int height,
  String outPath,
  CalibrationKind kind,
) {
  // `stackBand` drops a short frame from the band rather than padding it with
  // zeroes, which is right for lights but wrong here: if every input was
  // truncated the master comes out black, a black dark subtracts nothing, and
  // the run reports "calibrated with N darks" while having done nothing at
  // all. The flat side is caught later by `flatTooDark`; the dark side has no
  // such backstop, so the length check happens here for both.
  final expected = width * height * 3;
  for (final p in rawPaths) {
    final f = File(p);
    if (!f.existsSync() || f.lengthSync() != expected) {
      throw CalibrationException(kind, CalibrationProblem.truncated);
    }
  }
  final frames = [
    for (final p in rawPaths)
      AlignedFrame(
        path: p,
        transform: Similarity.identity,
        sourceWidth: width,
        sourceHeight: height,
      ),
  ];
  final out = File(outPath).openSync(mode: FileMode.write);
  try {
    for (var y0 = 0; y0 < height; y0 += kStackBandRows) {
      final y1 = (y0 + kStackBandRows) > height ? height : y0 + kStackBandRows;
      out.writeFromSync(stackBand(frames, width, y0, y1, StackMode.median));
    }
  } finally {
    out.closeSync();
  }
}

/// Per-channel mean of a master flat, read band by band.
///
/// Throws [CalibrationException] when the file is the wrong length (a
/// truncated scratch write) or so dark that it cannot be a flat.
List<double> measureFlatMeans(String flatPath, int width, int height) {
  final expected = width * height * 3;
  final f = File(flatPath);
  if (!f.existsSync() || f.lengthSync() != expected) {
    throw CalibrationException(CalibrationKind.flat, CalibrationProblem.truncated);
  }
  final sums = <double>[0, 0, 0];
  final handle = f.openSync();
  try {
    final rowBytes = width * 3;
    for (var y0 = 0; y0 < height; y0 += kCalibrationBandRows) {
      final rows =
          (y0 + kCalibrationBandRows) > height ? height - y0 : kCalibrationBandRows;
      final band = handle.readSync(rows * rowBytes);
      for (var i = 0; i < band.length; i += 3) {
        sums[0] += band[i];
        sums[1] += band[i + 1];
        sums[2] += band[i + 2];
      }
    }
  } finally {
    handle.closeSync();
  }
  final px = width * height;
  final means = [sums[0] / px, sums[1] / px, sums[2] / px];
  if (means[0] < kMinFlatMean && means[1] < kMinFlatMean && means[2] < kMinFlatMean) {
    throw CalibrationException(CalibrationKind.flat, CalibrationProblem.flatTooDark);
  }
  return means;
}

/// Apply the masters to one decoded light frame, in place.
///
/// `v ← clamp((v − dark) × meanFlat[channel] / max(1, flat))`, per channel,
/// exactly the order DeepSkyStacker applies them in (dark first: the flat
/// itself is only meaningful once the offset is gone).
void applyCalibration(
  Uint8List rgb,
  int width,
  int height,
  MasterFrames masters,
) {
  if (masters.isEmpty) return;
  final expected = width * height * 3;
  if (rgb.length != expected) {
    throw CalibrationException(CalibrationKind.dark, CalibrationProblem.sizeMismatch);
  }
  if (masters.width != width || masters.height != height) {
    throw CalibrationException(
      masters.darkPath != null ? CalibrationKind.dark : CalibrationKind.flat,
      CalibrationProblem.sizeMismatch,
    );
  }
  final dark = _openMaster(masters.darkPath, expected, CalibrationKind.dark);
  final flat = _openMaster(masters.flatPath, expected, CalibrationKind.flat);
  final fm = masters.flatMeans;
  try {
    final rowBytes = width * 3;
    var base = 0;
    for (var y0 = 0; y0 < height; y0 += kCalibrationBandRows) {
      final rows =
          (y0 + kCalibrationBandRows) > height ? height - y0 : kCalibrationBandRows;
      final n = rows * rowBytes;
      final darkBand = dark?.readSync(n);
      final flatBand = flat?.readSync(n);
      for (var i = 0; i < n; i += 3) {
        for (var ch = 0; ch < 3; ch++) {
          var v = rgb[base + i + ch].toDouble();
          if (darkBand != null) {
            v -= darkBand[i + ch];
            if (v < 0) v = 0;
          }
          if (flatBand != null) {
            final d = flatBand[i + ch].toDouble();
            v = v * fm[ch] / (d < 1 ? 1 : d);
          }
          rgb[base + i + ch] = v < 0 ? 0 : (v > 255 ? 255 : v.round());
        }
      }
      base += n;
    }
  } finally {
    dark?.closeSync();
    flat?.closeSync();
  }
}

RandomAccessFile? _openMaster(String? path, int expected, CalibrationKind kind) {
  if (path == null) return null;
  final f = File(path);
  if (!f.existsSync() || f.lengthSync() != expected) {
    throw CalibrationException(kind, CalibrationProblem.truncated);
  }
  return f.openSync();
}
