/// Turns raw per-frame pitch estimates into what a tuner shows: a stable
/// note name, a smoothed cents needle, and "no signal / too quiet" states.
/// Pure Dart, unit-tested with synthetic estimate sequences.
library;

import '../music/theory.dart';
import 'yin.dart';

enum SignalState { silent, quiet, tracking }

class TunerReading {
  const TunerReading({
    required this.state,
    this.midi,
    this.cents,
    this.frequency,
    this.level = 0,
    this.stable = false,
  });

  final SignalState state;

  /// Nearest MIDI note, when tracking.
  final int? midi;

  /// Deviation from [midi] in cents, smoothed, −50..50.
  final double? cents;
  final double? frequency;

  /// Input level 0..1 (RMS scaled for a meter).
  final double level;

  /// True once the same note has been held for a few frames — the moment
  /// worth logging as an accuracy sample.
  final bool stable;

  bool get hasPitch => state == SignalState.tracking && midi != null;

  bool get inTune => cents != null && cents!.abs() <= PitchTracker.inTuneCents;

  static const none = TunerReading(state: SignalState.silent);
}

class PitchTracker {
  PitchTracker({
    this.a4 = 440.0,
    this.holdFrames = 8,
    this.stableFrames = 3,
    this.centsSmoothing = 0.35,
    this.quietRms = 0.012,
  });

  /// |cents| at or below this counts as in tune (a needle inside the green
  /// band; most tuners use ±5).
  static const double inTuneCents = 5.0;

  double a4;

  /// Frames of silence before the display lets go of the last note (keeps
  /// the needle from flickering between plucks).
  final int holdFrames;

  /// Consecutive frames on the same note before it is called stable.
  final int stableFrames;

  /// Exponential smoothing factor for the cents needle (1 = no smoothing).
  final double centsSmoothing;

  /// RMS below which we say "too quiet" even if a pitch was found.
  final double quietRms;

  int? _midi;
  double? _cents;
  double? _freq;
  int _silentRun = 0;
  int _sameRun = 0;
  double _level = 0;

  /// Median-of-three buffer on the raw MIDI value; kills one-frame blips.
  final List<double> _recent = [];

  TunerReading get current => _reading(_midi == null
      ? SignalState.silent
      : SignalState.tracking);

  void reset() {
    _midi = null;
    _cents = null;
    _freq = null;
    _silentRun = 0;
    _sameRun = 0;
    _recent.clear();
    _level = 0;
  }

  /// Feed one analysis result (null = no pitch found in that frame).
  TunerReading push(PitchEstimate? e, {double? rms}) {
    final level = (e?.rms ?? rms ?? 0.0);
    _level = _level * 0.6 + (level * 12).clamp(0.0, 1.0) * 0.4;

    if (e == null || e.confidence < 0.5) {
      _silentRun++;
      if (_silentRun > holdFrames) {
        final quiet = level > 0 && level >= quietRms * 0.4;
        reset();
        _level = quiet ? _level : 0;
        return _reading(quiet ? SignalState.quiet : SignalState.silent);
      }
      // Hold the last reading through the gap, but it is no longer "stable".
      _sameRun = 0;
      return _reading(SignalState.tracking, stable: false);
    }
    _silentRun = 0;

    final rawMidi = frequencyToMidi(e.frequency, a4: a4);
    _recent.add(rawMidi);
    if (_recent.length > 3) _recent.removeAt(0);
    final sorted = [..._recent]..sort();
    final midiF = sorted[sorted.length ~/ 2];

    final nearest = midiF.round();
    var cents = (midiF - nearest) * 100.0;

    if (_midi == nearest) {
      _sameRun++;
      _cents = _cents == null
          ? cents
          : _cents! + (cents - _cents!) * centsSmoothing;
    } else {
      // A different note: switch immediately (a tuner that lags a semitone
      // feels broken) but restart the stability count and the smoother.
      _midi = nearest;
      _sameRun = 1;
      _cents = cents;
    }
    _freq = e.frequency;
    if (e.rms < quietRms) return _reading(SignalState.quiet, stable: false);
    return _reading(SignalState.tracking, stable: _sameRun >= stableFrames);
  }

  TunerReading _reading(SignalState state, {bool stable = false}) => TunerReading(
        state: state,
        midi: state == SignalState.silent ? null : _midi,
        cents: state == SignalState.silent ? null : _cents?.clamp(-50.0, 50.0),
        frequency: state == SignalState.silent ? null : _freq,
        level: _level,
        stable: stable,
      );
}
