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

  group('tap tempo', () {
    test('four even taps at 120 bpm', () {
      final t = TapTempo();
      final start = DateTime(2026, 1, 1, 12);
      int? bpm;
      for (var i = 0; i < 4; i++) {
        bpm = t.tap(start.add(Duration(milliseconds: 500 * i)));
      }
      expect(bpm, 120);
    });

    test('median ignores one wild tap', () {
      final t = TapTempo();
      final start = DateTime(2026, 1, 1, 12);
      final gaps = [600, 600, 200, 600, 600]; // ms
      var at = start;
      int? bpm = t.tap(at);
      for (final g in gaps) {
        at = at.add(Duration(milliseconds: g));
        bpm = t.tap(at);
      }
      expect(bpm, 100);
    });

    test('a long pause restarts the measurement', () {
      final t = TapTempo();
      final start = DateTime(2026, 1, 1, 12);
      t.tap(start);
      t.tap(start.add(const Duration(milliseconds: 500)));
      expect(t.tap(start.add(const Duration(seconds: 10))), isNull);
      expect(t.tap(start.add(const Duration(seconds: 10, milliseconds: 400))), 150);
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
