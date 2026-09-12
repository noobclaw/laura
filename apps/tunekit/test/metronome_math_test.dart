import 'package:flutter_test/flutter_test.dart';
import 'package:tunekit/tool/music/metronome_math.dart';

void main() {
  const fourFour = TimeSignature(4, 4, free: true);
  const sixEight = TimeSignature(6, 8);

  group('schedule', () {
    test('120 bpm quarter = 0.5 s per tick; eighths halve it', () {
      expect(tickIntervalSeconds(120, Subdivision.quarter, fourFour), closeTo(0.5, 1e-12));
      expect(tickIntervalSeconds(120, Subdivision.eighth, fourFour), closeTo(0.25, 1e-12));
      expect(tickIntervalSeconds(120, Subdivision.triplet, fourFour), closeTo(0.5 / 3, 1e-12));
      expect(tickIntervalSeconds(120, Subdivision.sixteenth, fourFour), closeTo(0.125, 1e-12));
    });

    test('tick times are multiplied, not accumulated: no drift at tick 10 000', () {
      // 0.5 s × 10 000 = exactly 5000 s at 120 bpm.
      expect(tickTimeSeconds(10000, 120, Subdivision.quarter, fourFour), closeTo(5000, 1e-9));
      expect(tickSample(10000, 120, Subdivision.quarter, fourFour, 48000), 240000000);
      // At 4.41 kHz-unfriendly tempos the rounding stays within one sample.
      final s = tickSample(9999, 137, Subdivision.triplet, fourFour, 44100);
      final exact = 9999 * 60 / 137 / 3 * 44100;
      expect((s - exact).abs(), lessThan(0.5));
    });

    test('accent on beat 1 in 4/4, subdivisions in between', () {
      final kinds = [for (var i = 0; i < 8; i++) tickKindAt(i, Subdivision.eighth, fourFour)];
      expect(kinds, [
        TickKind.accent, TickKind.sub,
        TickKind.beat, TickKind.sub,
        TickKind.beat, TickKind.sub,
        TickKind.beat, TickKind.sub,
      ]);
      expect(tickKindAt(8, Subdivision.eighth, fourFour), TickKind.accent);
      expect(beatAt(5, Subdivision.eighth, fourFour), 2);
    });

    test('6/8 accents beats 1 and 4', () {
      expect(sixEight.isCompound, isTrue);
      expect(sixEight.accents, {0, 3});
      final kinds = [for (var i = 0; i < 6; i++) tickKindAt(i, Subdivision.quarter, sixEight)];
      expect(kinds, [
        TickKind.accent, TickKind.beat, TickKind.beat,
        TickKind.accent, TickKind.beat, TickKind.beat,
      ]);
    });

    test('bpm is clamped to 30..300', () {
      expect(clampBpm(5), 30);
      expect(clampBpm(999), 300);
      expect(clampBpm(100), 100);
    });

    test('free tier covers 2/4 3/4 4/4 and quarter/eighth', () {
      expect(kTimeSignatures.where((s) => s.free).map((s) => s.label), ['2/4', '3/4', '4/4']);
      expect(Subdivision.values.where((s) => s.free), [Subdivision.quarter, Subdivision.eighth]);
    });
  });

  group('tap tempo (Tack rules: mean of ≤20, ±50 % tempo / 3× interval reset)', () {
    final start = DateTime(2026, 1, 1, 12);

    test('four even taps at 120 bpm', () {
      final t = TapTempo();
      int? bpm;
      for (var i = 0; i < 4; i++) {
        bpm = t.tap(start.add(Duration(milliseconds: 500 * i)));
      }
      expect(bpm, 120);
      expect(t.tapCount, 4);
    });

    test('mean of the window, not the last interval', () {
      final t = TapTempo();
      var at = start;
      int? bpm = t.tap(at);
      for (final g in [480, 520, 500, 500]) {
        at = at.add(Duration(milliseconds: g));
        bpm = t.tap(at);
      }
      expect(t.meanIntervalMs, 500);
      expect(bpm, 120);
    });

    test('a tap 3× faster restarts the count (≥ +50 % tempo) and the next tap restarts again', () {
      // 600 600 | 200 | 600 600: the 200 ms tap is discarded together with
      // the history, the following 600 ms tap discards the 200, and the
      // last two 600 ms taps agree on 100 bpm again.
      final t = TapTempo();
      final gaps = [600, 600, 200, 600, 600];
      final got = <int?>[];
      var at = start;
      t.tap(at);
      for (final g in gaps) {
        at = at.add(Duration(milliseconds: g));
        got.add(t.tap(at));
      }
      expect(got, [100, 100, null, null, 100]);
    });

    test('a long pause (> 3× mean) restarts; the estimate is back two taps later', () {
      final t = TapTempo();
      t.tap(start);
      expect(t.tap(start.add(const Duration(milliseconds: 500))), 120);
      expect(t.tap(start.add(const Duration(seconds: 10))), isNull);
      expect(t.tap(start.add(const Duration(seconds: 10, milliseconds: 400))), isNull);
      expect(t.tap(start.add(const Duration(seconds: 10, milliseconds: 800))), 150);
    });

    test('a gradual accelerando within ±50 % is averaged, not reset', () {
      final t = TapTempo();
      var at = start;
      t.tap(at);
      int? bpm;
      for (final g in [600, 560, 520, 480, 440]) {
        at = at.add(Duration(milliseconds: g));
        bpm = t.tap(at);
        expect(bpm, isNotNull, reason: 'gap $g must not reset');
      }
      expect(bpm, 60000 ~/ 520);
    });

    test('window keeps only the last 20 intervals', () {
      final t = TapTempo();
      var at = start;
      t.tap(at);
      int? bpm;
      // 20 taps at 500 ms, then 20 at 400 ms: the mean must have fully moved.
      for (var i = 0; i < 20; i++) {
        at = at.add(const Duration(milliseconds: 500));
        bpm = t.tap(at);
      }
      expect(bpm, 120);
      for (var i = 0; i < 20; i++) {
        at = at.add(const Duration(milliseconds: 400));
        bpm = t.tap(at);
      }
      expect(t.meanIntervalMs, 400);
      expect(bpm, 150);
    });

    test('reset clears everything', () {
      final t = TapTempo();
      t.tap(start);
      t.tap(start.add(const Duration(milliseconds: 500)));
      t.reset();
      expect(t.tapCount, 0);
      expect(t.tap(start.add(const Duration(seconds: 5))), isNull);
    });
  });

  group('click synthesis', () {
    test('click decays to silence within its length', () {
      for (final kind in TickKind.values) {
        final len = clickLengthSeconds(kind);
        expect(clickSample(0.0005, kind).abs(), greaterThan(0));
        expect(clickSample(len, kind).abs(), lessThan(0.01));
      }
    });

    test('tempo markings are monotonic', () {
      expect(tempoMarking(40), 'Largo');
      expect(tempoMarking(100), 'Andante');
      expect(tempoMarking(140), 'Allegro');
      expect(tempoMarking(220), 'Prestissimo');
    });
  });
}
