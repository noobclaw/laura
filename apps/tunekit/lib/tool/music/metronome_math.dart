/// Pure metronome arithmetic, shared by the Dart UI and mirrored by the
/// native audio sequencers (AudioBridge.kt / AudioBridge.swift). Keeping it
/// here means the visual beat indicator and the unit tests reason about
/// exactly the schedule the audio thread renders.
library;

import 'dart:math' as math;

const int kMinBpm = 30;
const int kMaxBpm = 300;

int clampBpm(int bpm) => bpm.clamp(kMinBpm, kMaxBpm);

/// Note value each tick subdivides the beat into.
enum Subdivision {
  quarter(1, '♩', free: true),
  eighth(2, '♫', free: true),
  triplet(3, '♪³'),
  sixteenth(4, '♬');

  const Subdivision(this.perBeat, this.glyph, {this.free = false});

  /// Ticks per beat.
  final int perBeat;
  final String glyph;
  final bool free;
}

class TimeSignature {
  const TimeSignature(this.beats, this.unit, {this.free = false});

  /// Beats per bar.
  final int beats;

  /// Note value of one beat (4 = quarter, 8 = eighth).
  final int unit;
  final bool free;

  String get label => '$beats/$unit';

  /// In compound metres (6/8) the pulse is the dotted quarter, so a "beat"
  /// for tempo purposes lasts three eighths. We keep the click on every
  /// eighth but accent 1 and 4, which is how a 6/8 metronome is played.
  bool get isCompound => unit == 8 && beats % 3 == 0;

  /// Beats that get an accent (0-based).
  Set<int> get accents => isCompound
      ? {for (var i = 0; i < beats; i += 3) i}
      : {0};

  @override
  bool operator ==(Object other) =>
      other is TimeSignature && other.beats == beats && other.unit == unit;

  @override
  int get hashCode => Object.hash(beats, unit);
}

const List<TimeSignature> kTimeSignatures = [
  TimeSignature(2, 4, free: true),
  TimeSignature(3, 4, free: true),
  TimeSignature(4, 4, free: true),
  TimeSignature(6, 8),
];

/// Kind of click to render for one tick.
enum TickKind { accent, beat, sub }

/// Seconds between two consecutive ticks.
double tickIntervalSeconds(int bpm, Subdivision sub, TimeSignature sig) {
  // BPM always counts the notated beat unit. In 6/8 the user sets the
  // eighth-note tempo × (dotted-quarter feel is up to them); this keeps the
  // displayed number honest with what the click does.
  return 60.0 / bpm / sub.perBeat;
}

/// Which click plays at tick [index] (0-based since start).
TickKind tickKindAt(int index, Subdivision sub, TimeSignature sig) {
  final perBar = sig.beats * sub.perBeat;
  final inBar = index % perBar;
  final subInBeat = inBar % sub.perBeat;
  if (subInBeat != 0) return TickKind.sub;
  final beat = inBar ~/ sub.perBeat;
  return sig.accents.contains(beat) ? TickKind.accent : TickKind.beat;
}

/// Beat number (0-based within the bar) for tick [index].
int beatAt(int index, Subdivision sub, TimeSignature sig) =>
    (index % (sig.beats * sub.perBeat)) ~/ sub.perBeat;

/// Absolute time of tick [index] from a start time, in seconds. Ticks are
/// placed by multiplying, never by accumulating a rounded interval, so tick
/// 10 000 is exactly where it belongs.
double tickTimeSeconds(int index, int bpm, Subdivision sub, TimeSignature sig) =>
    index * tickIntervalSeconds(bpm, sub, sig);

/// Sample position of tick [index] at [sampleRate] Hz (what the native
/// sequencer computes; floored to a frame).
int tickSample(int index, int bpm, Subdivision sub, TimeSignature sig, int sampleRate) =>
    (tickTimeSeconds(index, bpm, sub, sig) * sampleRate).round();

/// Italian tempo marking for the current BPM, purely informative.
String tempoMarking(int bpm) {
  if (bpm < 40) return 'Grave';
  if (bpm < 60) return 'Largo';
  if (bpm < 66) return 'Larghetto';
  if (bpm < 76) return 'Adagio';
  if (bpm < 108) return 'Andante';
  if (bpm < 120) return 'Moderato';
  if (bpm < 156) return 'Allegro';
  if (bpm < 176) return 'Vivace';
  if (bpm < 200) return 'Presto';
  return 'Prestissimo';
}

/// Tap-tempo estimator: median of the recent inter-tap intervals, which
/// shrugs off one mistimed tap better than a mean. Taps more than
/// [resetAfter] apart start a new measurement.
class TapTempo {
  TapTempo({this.window = 6, this.resetAfter = const Duration(seconds: 2)});

  final int window;
  final Duration resetAfter;
  final List<Duration> _intervals = [];
  DateTime? _last;

  int get tapCount => _intervals.length + (_last == null ? 0 : 1);

  /// Register a tap at [now]; returns the BPM estimate once two taps exist.
  int? tap(DateTime now) {
    final last = _last;
    _last = now;
    if (last == null) return null;
    final gap = now.difference(last);
    if (gap > resetAfter) {
      _intervals.clear();
      return null;
    }
    _intervals.add(gap);
    if (_intervals.length > window) _intervals.removeAt(0);
    final sorted = [..._intervals]..sort();
    final mid = sorted[sorted.length ~/ 2];
    final median = sorted.length.isEven
        ? (sorted[sorted.length ~/ 2 - 1] + mid) ~/ 2
        : mid;
    if (median.inMicroseconds == 0) return null;
    final bpm = (60e6 / median.inMicroseconds).round();
    return clampBpm(bpm);
  }

  void reset() {
    _intervals.clear();
    _last = null;
  }
}

/// A short percussive click rendered arithmetically (no sample assets).
/// Mirrors the native synthesis so tests can assert its length; the actual
/// audio is generated on the native side with the same formula:
///   y(t) = sin(2π f t) · e^(−t/τ), τ = 6 ms (accent 8 ms).
double clickSample(double t, TickKind kind) {
  final f = switch (kind) {
    TickKind.accent => 1760.0,
    TickKind.beat => 1320.0,
    TickKind.sub => 990.0,
  };
  final tau = kind == TickKind.accent ? 0.008 : 0.006;
  final gain = switch (kind) {
    TickKind.accent => 1.0,
    TickKind.beat => 0.8,
    TickKind.sub => 0.45,
  };
  return gain * math.sin(2 * math.pi * f * t) * math.exp(-t / tau);
}

/// Length of the synthesised click in seconds (≈ 5 τ).
double clickLengthSeconds(TickKind kind) =>
    kind == TickKind.accent ? 0.040 : 0.030;
