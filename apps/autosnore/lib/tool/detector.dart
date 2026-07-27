import 'dart:math' as math;

import 'audio_math.dart';
import 'models.dart';

/// Tunables for [SnoreDetector]. Defaults target a phone on a bedside table.
class SnoreConfig {
  const SnoreConfig({
    this.baseThresholdDb = 12.0,
    this.absoluteFloorDb = -50.0,
    this.minEventMs = 350,
    this.mergeGapMs = 400,
    this.maxEventMs = 20000,
    this.baselineAlpha = 0.05,
    this.sensitivity = 0.5,
  });

  /// How far a sample must rise above the adaptive noise baseline to count.
  final double baseThresholdDb;

  /// Samples quieter than this (dBFS) never count, whatever the baseline —
  /// stops ambient hiss in a silent room from registering.
  final double absoluteFloorDb;

  /// Shortest run (ms) above threshold that qualifies as an event; filters clicks.
  final int minEventMs;

  /// A dip below threshold shorter than this keeps the current event open
  /// (a single snore has brief quiet spots).
  final int mergeGapMs;

  /// Hard cap on a single continuous event. Beyond this the event is closed and
  /// the baseline is snapped up to the current level, so a steadily loud room
  /// (fan/AC/rain) can't lock the detector into one whole-night "event".
  final int maxEventMs;

  /// EMA rate the quiet baseline adapts at (only updated below threshold).
  final double baselineAlpha;

  /// 0..1 user setting: higher = more sensitive (lower effective threshold).
  final double sensitivity;

  /// Effective rise threshold after applying sensitivity: 0.5 → base,
  /// 1.0 → base-6 dB (more events), 0.0 → base+6 dB (fewer).
  double get effectiveThresholdDb => baseThresholdDb - (sensitivity - 0.5) * 12.0;
}

/// Streaming detector: feed it dBFS samples with timestamps and it emits
/// [SnoreEvent]s as runs of raised loudness complete. Pure and deterministic —
/// no plugins, no wall clock — so it is fully unit-testable.
class SnoreDetector {
  SnoreDetector({SnoreConfig config = const SnoreConfig()})
      : _cfg = config,
        _baseline = config.absoluteFloorDb - 5.0;

  final SnoreConfig _cfg;
  double _baseline;

  bool _inEvent = false;
  int _evtStart = 0;
  int _lastAbove = 0;
  double _peak = kSilenceDb;
  double _sum = 0;
  int _cnt = 0;

  double get baseline => _baseline;

  /// Feed one sample. Returns a completed event when a run just ended, else null.
  SnoreEvent? addSample(int tMs, double db) {
    final double threshold =
        math.max(_baseline + _cfg.effectiveThresholdDb, _cfg.absoluteFloorDb);
    final bool above = db >= threshold;

    if (above) {
      if (!_inEvent) {
        _inEvent = true;
        _evtStart = tMs;
        _peak = db;
        _sum = db;
        _cnt = 1;
      } else {
        if (db > _peak) _peak = db;
        _sum += db;
        _cnt += 1;
      }
      _lastAbove = tMs;
      // Steady-noise guard: a run this long is not a snore — close it and
      // recalibrate the baseline to the sustained level so it stops firing.
      if (tMs - _evtStart >= _cfg.maxEventMs) {
        final SnoreEvent? evt = _closeEvent();
        _baseline = db;
        return evt;
      }
      return null;
    }

    // Below threshold: let the quiet baseline drift toward ambient.
    _baseline += (db - _baseline) * _cfg.baselineAlpha;

    if (_inEvent && (tMs - _lastAbove) >= _cfg.mergeGapMs) {
      return _closeEvent();
    }
    return null;
  }

  /// Flush any open event at end of stream. Call once when recording stops.
  SnoreEvent? finish() => _inEvent ? _closeEvent() : null;

  SnoreEvent? _closeEvent() {
    final int dur = _lastAbove - _evtStart;
    final SnoreEvent? evt = dur >= _cfg.minEventMs
        ? SnoreEvent(
            startMs: _evtStart,
            durationMs: dur,
            peakDb: _peak,
            avgDb: _cnt > 0 ? _sum / _cnt : _peak,
          )
        : null;
    _inEvent = false;
    _peak = kSilenceDb;
    _sum = 0;
    _cnt = 0;
    return evt;
  }
}
