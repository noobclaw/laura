import 'dart:async';
import 'dart:math' as math;

/// One encode attempt: JPEG/WebP quality plus a uniform dimension scale
/// (1.0 = original pixels). Pure data so tests can drive the search with a
/// fake encoder and the runtime can hand it to a native codec.
class EncodeParams {
  const EncodeParams({required this.quality, required this.scale});
  final int quality;
  final double scale;

  @override
  String toString() => 'q=$quality scale=${scale.toStringAsFixed(3)}';
}

/// Result of a target-size search.
class SizeSearchResult {
  const SizeSearchResult({
    required this.params,
    required this.bytes,
    required this.attempts,
    required this.hitTarget,
  });

  final EncodeParams params;

  /// Encoded size of the chosen attempt.
  final int bytes;
  final int attempts;

  /// False when even the smallest allowed quality/scale stayed over target;
  /// [params] is then the smallest result found.
  final bool hitTarget;
}

/// Callback that encodes with [p] and returns the byte length.
typedef SizeProbe = FutureOr<int> Function(EncodeParams p);

/// Find the highest quality (then largest scale) whose encoded size is
/// ≤ [targetBytes].
///
/// Strategy (adapted from ImageToolbox's compress-by-size loop, rewritten):
/// 1. Try [startQuality] at scale 1. If it already fits and is within
///    [tolerance] of the target, stop.
/// 2. Binary-search quality in `[minQuality, maxQuality]` at scale 1 — a
///    monotone probe converges in ≤ 7 attempts for a 1..100 range.
/// 3. If [minQuality] still overshoots, shrink the dimensions: the scale is
///    estimated from the byte ratio (`sqrt(target/size)`, JPEG size grows
///    roughly linearly with pixel count) with a safety factor, then the
///    quality search is repeated at that scale. At most [maxScaleRounds]
///    shrink rounds; the scale never drops below [minScale].
///
/// Every attempt costs one encode, so the caller passes a probe that is as
/// cheap as the platform allows (native codec, no re-decode of the source).
Future<SizeSearchResult> searchForTargetSize({
  required int targetBytes,
  required SizeProbe probe,
  int startQuality = 85,
  int minQuality = 20,
  int maxQuality = 95,
  double tolerance = 0.10,
  int maxScaleRounds = 3,
  double minScale = 0.15,
}) async {
  assert(targetBytes > 0);
  assert(minQuality <= maxQuality);
  var attempts = 0;
  EncodeParams? bestFit; // largest under target so far
  var bestFitBytes = 0;
  EncodeParams? smallest; // absolute smallest, for the failure case
  var smallestBytes = 1 << 62;

  Future<int> tryParams(EncodeParams p) async {
    attempts++;
    final n = await probe(p);
    if (n <= targetBytes && n > bestFitBytes) {
      bestFit = p;
      bestFitBytes = n;
    }
    if (n < smallestBytes) {
      smallest = p;
      smallestBytes = n;
    }
    return n;
  }

  bool closeEnough(int n) =>
      n <= targetBytes && n >= targetBytes * (1 - tolerance);

  var scale = 1.0;
  for (var round = 0; round <= maxScaleRounds; round++) {
    // Quick first probe at the preferred quality.
    final first = await tryParams(EncodeParams(
        quality: startQuality.clamp(minQuality, maxQuality), scale: scale));
    if (closeEnough(first)) break;

    int lo;
    int hi;
    if (first > targetBytes) {
      lo = minQuality;
      hi = startQuality - 1;
    } else {
      lo = startQuality + 1;
      hi = maxQuality;
    }
    var done = false;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final n = await tryParams(EncodeParams(quality: mid, scale: scale));
      if (closeEnough(n)) {
        done = true;
        break;
      }
      if (n > targetBytes) {
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }
    if (done || bestFit != null) break;

    // Even minQuality is too big at this scale: shrink pixels.
    if (round == maxScaleRounds) break;
    final ratio = targetBytes / smallestBytes;
    final next = scale * math.sqrt(ratio) * 0.9;
    scale = math.max(minScale, next);
    if (scale >= 0.999) break;
  }

  if (bestFit != null) {
    return SizeSearchResult(
        params: bestFit!, bytes: bestFitBytes, attempts: attempts, hitTarget: true);
  }
  return SizeSearchResult(
      params: smallest ?? EncodeParams(quality: minQuality, scale: scale),
      bytes: smallestBytes,
      attempts: attempts,
      hitTarget: false);
}
