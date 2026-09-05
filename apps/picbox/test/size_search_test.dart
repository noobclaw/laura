import 'package:flutter_test/flutter_test.dart';
import 'package:picbox/tool/engine/size_search.dart';

/// Fake encoder: bytes grow with quality and with pixel count (scale²).
int fakeSize(EncodeParams p, {int base = 4 * 1024 * 1024}) =>
    (base * (0.15 + 0.85 * p.quality / 100) * p.scale * p.scale).round();

void main() {
  test('finds the highest quality under target without scaling', () async {
    final probes = <EncodeParams>[];
    final r = await searchForTargetSize(
      targetBytes: 2 * 1024 * 1024,
      probe: (p) {
        probes.add(p);
        return fakeSize(p);
      },
    );
    expect(r.hitTarget, isTrue);
    expect(r.bytes, lessThanOrEqualTo(2 * 1024 * 1024));
    // Lands inside the tolerance band just under the target (the search
    // stops early once it is within 10 %, trading a point or two of quality
    // for one fewer encode).
    expect(r.bytes, greaterThanOrEqualTo(2 * 1024 * 1024 * 0.9));
    expect(r.params.scale, 1.0);
    expect(r.params.quality, inInclusiveRange(20, 95));
    expect(r.attempts, lessThanOrEqualTo(8));
  });

  test('stops early when the first probe is already close enough', () async {
    // Target such that q=85 lands within 10 % under.
    final q85 = fakeSize(const EncodeParams(quality: 85, scale: 1));
    final r = await searchForTargetSize(targetBytes: (q85 * 1.05).round(), probe: fakeSize);
    expect(r.attempts, 1);
    expect(r.params.quality, 85);
  });

  test('scales dimensions down when minimum quality still overshoots', () async {
    final r = await searchForTargetSize(
      targetBytes: 200 * 1024,
      probe: fakeSize,
    );
    expect(r.hitTarget, isTrue);
    expect(r.params.scale, lessThan(1.0));
    expect(r.params.scale, greaterThanOrEqualTo(0.15));
    expect(r.bytes, lessThanOrEqualTo(200 * 1024));
  });

  test('reports failure when even the smallest scale is too big', () async {
    final r = await searchForTargetSize(
      targetBytes: 1024,
      probe: fakeSize,
      maxScaleRounds: 2,
    );
    expect(r.hitTarget, isFalse);
    expect(r.bytes, greaterThan(1024));
    // Still returns the smallest thing it found.
    expect(r.params.quality, 20);
  });

  test('lossless mode (min == max quality) only scales', () async {
    final r = await searchForTargetSize(
      targetBytes: 1 * 1024 * 1024,
      minQuality: 100,
      maxQuality: 100,
      startQuality: 100,
      probe: fakeSize,
    );
    expect(r.hitTarget, isTrue);
    expect(r.params.quality, 100);
    expect(r.params.scale, lessThan(1.0));
  });

  test('never probes outside the quality bounds', () async {
    final seen = <int>{};
    await searchForTargetSize(
      targetBytes: 900 * 1024,
      minQuality: 30,
      maxQuality: 90,
      probe: (p) {
        seen.add(p.quality);
        return fakeSize(p);
      },
    );
    expect(seen.every((q) => q >= 30 && q <= 90), isTrue);
  });
}
