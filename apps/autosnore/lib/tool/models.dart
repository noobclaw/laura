import 'dart:math' as math;

/// One detected snore / loud-noise event during a night. All fields are plain
/// data; loudness is dBFS (≤ 0). JSON keys are stable identifiers — never
/// translated (PIPELINE i18n rule: logs/keys/filenames stay in English).
class SnoreEvent {
  const SnoreEvent({
    required this.startMs,
    required this.durationMs,
    required this.peakDb,
    required this.avgDb,
  });

  /// Milliseconds since Unix epoch when the event began.
  final int startMs;
  final int durationMs;
  final double peakDb;
  final double avgDb;

  Map<String, dynamic> toJson() => {
        'startMs': startMs,
        'durationMs': durationMs,
        'peakDb': peakDb,
        'avgDb': avgDb,
      };

  factory SnoreEvent.fromJson(Map<String, dynamic> j) => SnoreEvent(
        startMs: (j['startMs'] as num).toInt(),
        durationMs: (j['durationMs'] as num).toInt(),
        peakDb: (j['peakDb'] as num).toDouble(),
        avgDb: (j['avgDb'] as num).toDouble(),
      );
}

/// A qualitative band derived from the 0–100 snore score.
enum SnoreBand { quiet, mild, moderate, loud }

/// One night's recording: the window plus every detected event. Every summary
/// number (count, index, percent, score…) is a pure getter over [events] and
/// the window, so the whole aggregation is deterministic and unit-testable.
class SleepSession {
  const SleepSession({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.events,
    this.sensitivity = 0.5,
    this.endedEarly = false,
    this.interruptedMs = 0,
  });

  final String id;
  final int startMs;
  final int endMs;
  final List<SnoreEvent> events;

  /// Time during which the microphone stream delivered nothing (audio focus
  /// lost to a chime, an interruption the OS did not hand back, a stall).
  /// Shown in the report so a quiet night and a broken night look different.
  final int interruptedMs;

  /// Time the microphone was actually listening.
  int get listenedMs => math.max(0, durationMs - interruptedMs);

  /// Detector sensitivity in effect for this session (0..1), stored so a report
  /// can explain how it was measured.
  final double sensitivity;

  /// True when the night ended because the app left the foreground (call, user
  /// switched away) rather than by tapping Stop — surfaced in the report so an
  /// "all-night" recording that stopped at 00:47 isn't presented as complete.
  final bool endedEarly;

  int get durationMs => math.max(0, endMs - startMs);
  double get durationHours => durationMs / 3600000.0;

  int get snoreCount => events.length;

  int get totalSnoreMs {
    int t = 0;
    for (final e in events) {
      t += e.durationMs;
    }
    return t;
  }

  /// Events per hour of sleep. 0 when the session has no measurable duration.
  double get snoreIndexPerHour {
    final h = durationHours;
    if (h <= 0) return 0;
    return snoreCount / h;
  }

  /// Share of the night spent making noise, as a percentage (0..100).
  double get snorePercent {
    if (durationMs <= 0) return 0;
    return (totalSnoreMs / durationMs * 100).clamp(0, 100).toDouble();
  }

  SnoreEvent? get loudest {
    if (events.isEmpty) return null;
    SnoreEvent best = events.first;
    for (final e in events) {
      if (e.peakDb > best.peakDb) best = e;
    }
    return best;
  }

  /// Events whose start falls within a breathing-like interval (1.5–8 s) of a
  /// neighbouring event. Snoring is rhythmic, so a high share here separates
  /// real snoring from one-off random noises. Assumes [events] is time-ordered.
  int get rhythmicCount {
    if (events.length < 2) return 0;
    const int lo = 1500, hi = 8000;
    int count = 0;
    for (int i = 0; i < events.length; i++) {
      final int cur = events[i].startMs;
      bool rhythmic = false;
      if (i > 0) {
        final int gap = cur - events[i - 1].startMs;
        if (gap >= lo && gap <= hi) rhythmic = true;
      }
      if (!rhythmic && i < events.length - 1) {
        final int gap = events[i + 1].startMs - cur;
        if (gap >= lo && gap <= hi) rhythmic = true;
      }
      if (rhythmic) count++;
    }
    return count;
  }

  /// 0–100 "snore score": mostly how much of the night was noisy, nudged by how
  /// often. Deterministic and monotonic in both inputs.
  int get score {
    if (durationMs <= 0) return 0;
    final double raw = snorePercent * 2.0 + math.min(snoreIndexPerHour, 60) * 0.5;
    return raw.clamp(0, 100).round();
  }

  SnoreBand get band {
    final s = score;
    if (s < 10) return SnoreBand.quiet;
    if (s < 25) return SnoreBand.mild;
    if (s < 50) return SnoreBand.moderate;
    return SnoreBand.loud;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startMs': startMs,
        'endMs': endMs,
        'sensitivity': sensitivity,
        'endedEarly': endedEarly,
        'interruptedMs': interruptedMs,
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory SleepSession.fromJson(Map<String, dynamic> j) => SleepSession(
        id: j['id'] as String,
        startMs: (j['startMs'] as num).toInt(),
        endMs: (j['endMs'] as num).toInt(),
        sensitivity: (j['sensitivity'] as num?)?.toDouble() ?? 0.5,
        endedEarly: j['endedEarly'] as bool? ?? false,
        interruptedMs: (j['interruptedMs'] as num?)?.toInt() ?? 0,
        events: (j['events'] as List<dynamic>? ?? [])
            .map((e) => SnoreEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
