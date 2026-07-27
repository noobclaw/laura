import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart audio helpers. Kept free of any plugin so the loudness maths is
/// unit-testable without a microphone. Everything downstream (detection,
/// scoring) consumes the dBFS values this produces.

/// Practical floor returned for silence / empty buffers. 0 dBFS is full scale
/// (loudest a PCM16 sample can be); real room noise sits far below.
const double kSilenceDb = -160.0;

/// Root-mean-square loudness of a little-endian PCM 16-bit mono buffer, in
/// dBFS (decibels relative to full scale, always ≤ 0). Empty or near-silent
/// buffers return [kSilenceDb].
double rmsDbfsPcm16(Uint8List bytes) {
  final int n = bytes.length ~/ 2;
  if (n == 0) return kSilenceDb;
  final bd = ByteData.sublistView(bytes);
  double sumSq = 0;
  for (int i = 0; i < n; i++) {
    final int s = bd.getInt16(i * 2, Endian.little);
    final double v = s / 32768.0;
    sumSq += v * v;
  }
  final double rms = math.sqrt(sumSq / n);
  if (rms <= 1e-9) return kSilenceDb;
  return 20.0 * (math.log(rms) / math.ln10);
}
