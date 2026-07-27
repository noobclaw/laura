import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:autosnore/tool/audio_math.dart';
import 'package:autosnore/tool/detector.dart';
import 'package:autosnore/tool/models.dart';

/// Little-endian PCM16 mono buffer of [n] samples all at [amp].
Uint8List pcm(int n, int amp) {
  final bytes = Uint8List(n * 2);
  final bd = ByteData.sublistView(bytes);
  for (int i = 0; i < n; i++) {
    bd.setInt16(i * 2, amp, Endian.little);
  }
  return bytes;
}

/// Run the detector over a (timeMs, db) script, returning all events including
/// the one flushed at end of stream.
List<SnoreEvent> runDetector(
    SnoreDetector d, List<(int, double)> samples) {
  final out = <SnoreEvent>[];
  for (final (t, db) in samples) {
    final e = d.addSample(t, db);
    if (e != null) out.add(e);
  }
  final tail = d.finish();
  if (tail != null) out.add(tail);
  return out;
}

void main() {
  group('rmsDbfsPcm16', () {
    test('empty buffer is silence', () {
      expect(rmsDbfsPcm16(Uint8List(0)), kSilenceDb);
      expect(rmsDbfsPcm16(pcm(100, 0)), kSilenceDb);
    });

    test('full-scale is near 0 dBFS', () {
      expect(rmsDbfsPcm16(pcm(200, 32767)), greaterThan(-1.0));
      expect(rmsDbfsPcm16(pcm(200, 32767)), lessThanOrEqualTo(0.0));
    });

    test('tenth of full scale is about -20 dBFS', () {
      final db = rmsDbfsPcm16(pcm(200, 3277)); // 0.1 * 32768
      expect(db, closeTo(-20.0, 0.5));
    });

    test('louder input yields higher dBFS', () {
      final quiet = rmsDbfsPcm16(pcm(200, 300));
      final loud = rmsDbfsPcm16(pcm(200, 8000));
      expect(loud, greaterThan(quiet));
    });
  });

  group('SnoreConfig', () {
    test('sensitivity maps to effective threshold', () {
      expect(const SnoreConfig(sensitivity: 0.5).effectiveThresholdDb,
          closeTo(12.0, 1e-9));
      expect(const SnoreConfig(sensitivity: 1.0).effectiveThresholdDb,
          closeTo(6.0, 1e-9));
      expect(const SnoreConfig(sensitivity: 0.0).effectiveThresholdDb,
          closeTo(18.0, 1e-9));
    });
  });

  group('SnoreDetector', () {
    test('a sustained loud burst produces one event', () {
      final d = SnoreDetector();
      final samples = <(int, double)>[
        for (int t = 0; t <= 800; t += 200) (t, -55.0), // quiet
        for (int t = 1000; t <= 2000; t += 200) (t, -30.0), // loud ~1s
        for (int t = 2200; t <= 3000; t += 200) (t, -55.0), // quiet
      ];
      final events = runDetector(d, samples);
      expect(events.length, 1);
      expect(events.first.durationMs, 1000);
      expect(events.first.peakDb, closeTo(-30.0, 0.1));
    });

    test('a pure quiet night produces no events', () {
      final d = SnoreDetector();
      final samples = [for (int t = 0; t <= 5000; t += 200) (t, -58.0)];
      expect(runDetector(d, samples), isEmpty);
    });

    test('a too-short blip is filtered out', () {
      final d = SnoreDetector();
      final samples = <(int, double)>[
        for (int t = 0; t <= 800; t += 200) (t, -55.0),
        (1000, -25.0), // single 200ms blip < minEventMs
        for (int t = 1200; t <= 2000; t += 200) (t, -55.0),
      ];
      expect(runDetector(d, samples), isEmpty);
    });

    test('an event still open at end of stream is flushed', () {
      final d = SnoreDetector();
      final samples = <(int, double)>[
        for (int t = 0; t <= 800; t += 200) (t, -55.0),
        for (int t = 1000; t <= 2000; t += 200) (t, -28.0),
      ];
      final events = runDetector(d, samples);
      expect(events.length, 1);
      expect(events.first.startMs, 1000);
    });

    test('steady loud room does not lock into one whole-night event', () {
      // Continuous loud ambient for a minute: must be capped + recalibrated,
      // not emitted as a single 60s (or whole-night) "snore".
      final d = SnoreDetector(config: const SnoreConfig(maxEventMs: 20000));
      final samples = [for (int t = 0; t <= 60000; t += 200) (t, -30.0)];
      final events = runDetector(d, samples);
      expect(events.length, 1);
      expect(events.first.durationMs, lessThanOrEqualTo(20000));
    });
  });

  group('SleepSession aggregation', () {
    SleepSession make(List<SnoreEvent> events, {int hours = 1}) => SleepSession(
          id: 't',
          startMs: 0,
          endMs: hours * 3600000,
          events: events,
        );

    test('counts, index and percent', () {
      final s = make([
        const SnoreEvent(startMs: 0, durationMs: 1000, peakDb: -30, avgDb: -32),
        const SnoreEvent(
            startMs: 5000, durationMs: 2000, peakDb: -20, avgDb: -24),
      ]);
      expect(s.snoreCount, 2);
      expect(s.totalSnoreMs, 3000);
      expect(s.snoreIndexPerHour, closeTo(2.0, 1e-9));
      expect(s.snorePercent, closeTo(3000 / 3600000 * 100, 1e-9));
      expect(s.loudest!.peakDb, -20);
    });

    test('empty session is all zero and quiet', () {
      final s = make([]);
      expect(s.snoreCount, 0);
      expect(s.snoreIndexPerHour, 0);
      expect(s.snorePercent, 0);
      expect(s.loudest, isNull);
      expect(s.score, 0);
      expect(s.band, SnoreBand.quiet);
    });

    test('zero-duration session never divides by zero', () {
      final s = SleepSession(
          id: 'x',
          startMs: 100,
          endMs: 100,
          events: const [
            SnoreEvent(startMs: 100, durationMs: 10, peakDb: -20, avgDb: -22)
          ]);
      expect(s.snoreIndexPerHour, 0);
      expect(s.snorePercent, 0);
      expect(s.score, 0);
    });

    test('score is monotonic and banded', () {
      // ~30% of a 1h night noisy + high index → loud band.
      final many = [
        for (int i = 0; i < 100; i++)
          SnoreEvent(
              startMs: i * 10000, durationMs: 10000, peakDb: -15, avgDb: -18),
      ];
      final loud = SleepSession(
          id: 'l', startMs: 0, endMs: 3600000, events: many);
      expect(loud.snorePercent, greaterThan(25));
      expect(loud.score, greaterThan(50));
      expect(loud.band, SnoreBand.loud);
    });

    test('rhythmic events counted within breathing interval', () {
      final s = make([
        const SnoreEvent(startMs: 0, durationMs: 500, peakDb: -25, avgDb: -27),
        const SnoreEvent(
            startMs: 3000, durationMs: 500, peakDb: -25, avgDb: -27),
        const SnoreEvent(
            startMs: 6000, durationMs: 500, peakDb: -25, avgDb: -27),
        const SnoreEvent(
            startMs: 20000, durationMs: 500, peakDb: -25, avgDb: -27),
      ]);
      // First three are 3s apart (rhythmic); the last is isolated.
      expect(s.rhythmicCount, 3);
    });
  });

  group('JSON round-trip', () {
    test('SnoreEvent survives toJson/fromJson', () {
      const e =
          SnoreEvent(startMs: 123, durationMs: 456, peakDb: -12.5, avgDb: -18.2);
      final back = SnoreEvent.fromJson(e.toJson());
      expect(back.startMs, e.startMs);
      expect(back.durationMs, e.durationMs);
      expect(back.peakDb, e.peakDb);
      expect(back.avgDb, e.avgDb);
    });

    test('SleepSession survives toJson/fromJson', () {
      final s = SleepSession(
        id: 'night-1',
        startMs: 1000,
        endMs: 2000,
        sensitivity: 0.7,
        events: const [
          SnoreEvent(startMs: 1100, durationMs: 300, peakDb: -22, avgDb: -25),
        ],
      );
      final back = SleepSession.fromJson(s.toJson());
      expect(back.id, s.id);
      expect(back.startMs, s.startMs);
      expect(back.endMs, s.endMs);
      expect(back.sensitivity, 0.7);
      expect(back.endedEarly, false);
      expect(back.events.length, 1);
      expect(back.events.first.peakDb, -22);
    });

    test('endedEarly flag round-trips and defaults false on legacy JSON', () {
      final s = SleepSession(
          id: 'e', startMs: 0, endMs: 10, events: const [], endedEarly: true);
      expect(SleepSession.fromJson(s.toJson()).endedEarly, true);
      // Legacy record with no endedEarly key.
      final legacy = SleepSession.fromJson(
          {'id': 'l', 'startMs': 0, 'endMs': 10, 'events': []});
      expect(legacy.endedEarly, false);
    });
  });
}
