import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunekit/tool/music/theory.dart';
import 'package:tunekit/tool/pitch/pitch_tracker.dart';
import 'package:tunekit/tool/pitch/yin.dart';

/// Synthetic tone: fundamental plus optional harmonics, amplitude [amp].
Float32List tone(double hz, int n, double sr,
    {List<double> harmonics = const [1.0], double amp = 0.3, double noise = 0}) {
  final rng = math.Random(42);
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    var s = 0.0;
    for (var h = 0; h < harmonics.length; h++) {
      s += harmonics[h] * math.sin(2 * math.pi * hz * (h + 1) * t);
    }
    out[i] = (amp * s + noise * (rng.nextDouble() * 2 - 1)).clamp(-1, 1);
  }
  return out;
}

double centsOff(double measured, double target) =>
    1200 * (math.log(measured / target) / math.ln2);

void main() {
  const sr = 44100.0;
  final yin = YinDetector(sampleRate: sr);

  group('YIN', () {
    test('finds A4 on a pure sine within 1 cent', () {
      final e = yin.estimate(tone(440, yin.requiredSamples, sr));
      expect(e, isNotNull);
      expect(centsOff(e!.frequency, 440).abs(), lessThan(1));
      expect(e.confidence, greaterThan(0.9));
    });

    test('tracks a rich low E2 (82.41 Hz) without octave error', () {
      // A plucked string: strong harmonics, the 2nd louder than the 1st.
      final x = tone(82.41, yin.requiredSamples, sr,
          harmonics: const [0.8, 1.0, 0.6, 0.4, 0.2]);
      final e = yin.estimate(x);
      expect(e, isNotNull);
      expect(centsOff(e!.frequency, 82.41).abs(), lessThan(3));
    });

    test('reaches bass E1 (41.2 Hz) and violin E5 (659 Hz)', () {
      for (final hz in [41.2, 659.26, 1318.5]) {
        final e = yin.estimate(tone(hz, yin.requiredSamples, sr,
            harmonics: const [1.0, 0.5, 0.25]));
        expect(e, isNotNull, reason: '$hz Hz');
        expect(centsOff(e!.frequency, hz).abs(), lessThan(3), reason: '$hz Hz');
      }
    });

    test('survives moderate noise', () {
      final e = yin.estimate(tone(220, yin.requiredSamples, sr,
          harmonics: const [1.0, 0.4], noise: 0.05));
      expect(e, isNotNull);
      expect(centsOff(e!.frequency, 220).abs(), lessThan(3));
    });

    test('returns null for silence and for noise', () {
      expect(yin.estimate(Float32List(yin.requiredSamples)), isNull);
      expect(yin.estimate(tone(0, yin.requiredSamples, sr, amp: 0, noise: 0.2)), isNull);
    });

    test('too-short input is rejected', () {
      expect(yin.estimate(Float32List(100)), isNull);
    });
  });

  group('note mapping', () {
    test('A4 = 69, C4 = 60, names and octaves', () {
      expect(frequencyToMidi(440), closeTo(69, 1e-9));
      expect(midiToFrequency(60), closeTo(261.6256, 1e-3));
      expect(noteName(69), 'A4');
      expect(noteName(60), 'C4');
      expect(noteName(61), 'C#4');
      expect(noteName(61, flats: true), 'Db4');
      expect(noteName(40), 'E2');
    });

    test('reference pitch shifts the mapping', () {
      // 442 Hz played against A4=442 is exactly A4.
      expect(frequencyToMidi(442, a4: 442), closeTo(69, 1e-9));
      // Against A4=440 it reads +7.85 cents sharp.
      expect((frequencyToMidi(442) - 69) * 100, closeTo(7.85, 0.05));
    });
  });

  group('PitchTracker', () {
    test('locks a note, smooths cents and reports stability', () {
      final t = PitchTracker();
      TunerReading? r;
      for (var i = 0; i < 5; i++) {
        r = t.push(const PitchEstimate(frequency: 442, confidence: 0.95, rms: 0.05));
      }
      expect(r!.hasPitch, isTrue);
      expect(r.midi, 69);
      expect(r.cents, closeTo(7.85, 0.5));
      expect(r.stable, isTrue);
      expect(r.inTune, isFalse);
    });

    test('a one-frame blip does not change the note', () {
      final t = PitchTracker();
      for (var i = 0; i < 4; i++) {
        t.push(const PitchEstimate(frequency: 440, confidence: 0.95, rms: 0.05));
      }
      final blip = t.push(const PitchEstimate(frequency: 880, confidence: 0.95, rms: 0.05));
      expect(blip.midi, 69, reason: 'median-of-three absorbs a single octave blip');
      final back = t.push(const PitchEstimate(frequency: 440, confidence: 0.95, rms: 0.05));
      expect(back.midi, 69);
    });

    test('holds through a short gap, then goes silent', () {
      final t = PitchTracker(holdFrames: 3);
      for (var i = 0; i < 4; i++) {
        t.push(const PitchEstimate(frequency: 440, confidence: 0.95, rms: 0.05));
      }
      expect(t.push(null).hasPitch, isTrue);
      expect(t.push(null).hasPitch, isTrue);
      expect(t.push(null).hasPitch, isTrue);
      final gone = t.push(null);
      expect(gone.state, SignalState.silent);
      expect(gone.midi, isNull);
    });

    test('quiet input is flagged rather than shown as a reading', () {
      final t = PitchTracker();
      final r = t.push(const PitchEstimate(frequency: 440, confidence: 0.9, rms: 0.005));
      expect(r.state, SignalState.quiet);
      expect(r.stable, isFalse);
    });

    test('reference pitch is honoured', () {
      final t = PitchTracker(a4: 442);
      TunerReading? r;
      for (var i = 0; i < 4; i++) {
        r = t.push(const PitchEstimate(frequency: 442, confidence: 0.95, rms: 0.05));
      }
      expect(r!.midi, 69);
      expect(r.cents!.abs(), lessThan(0.1));
      expect(r.inTune, isTrue);
    });
  });
}
