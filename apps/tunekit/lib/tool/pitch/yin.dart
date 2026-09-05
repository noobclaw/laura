/// YIN fundamental-frequency estimator, implemented from the paper:
/// A. de Cheveigné & H. Kawahara, "YIN, a fundamental frequency estimator
/// for speech and music", JASA 111(4), 2002. Steps 1–5 of the paper:
/// difference function, cumulative mean normalised difference (CMND),
/// absolute threshold, parabolic interpolation. Step 6 (best local
/// estimate) is replaced by the RMS gate and the tracker's hysteresis,
/// which is enough for a monophonic tuner.
///
/// Pure Dart, no FFT: the cost is O(W · τmax) multiply-adds per analysis —
/// about 3 M for a 2048-sample window down to 30 Hz at 44.1 kHz, which is a
/// few milliseconds AOT and runs off the UI isolate (see pitch_worker.dart).
library;

import 'dart:math' as math;
import 'dart:typed_data';

class PitchEstimate {
  const PitchEstimate({
    required this.frequency,
    required this.confidence,
    required this.rms,
  });

  /// Fundamental in Hz.
  final double frequency;

  /// 1 − CMND at the chosen lag: ~1 for a clean periodic signal, lower for
  /// noise or transients.
  final double confidence;

  /// RMS level of the analysed window, 0..1.
  final double rms;
}

class YinDetector {
  YinDetector({
    required this.sampleRate,
    this.windowSize = 2048,
    this.minHz = 30.0,
    this.maxHz = 2200.0,
    this.threshold = 0.12,
    this.minRms = 0.004,
  })  : _tauMin = math.max(2, (sampleRate / maxHz).floor()),
        _tauMax = (sampleRate / minHz).ceil() {
    _cmnd = Float64List(_tauMax + 1);
  }

  final double sampleRate;

  /// Integration window W (paper: the window over which each lag is
  /// compared). The caller must hand over at least [requiredSamples].
  final int windowSize;
  final double minHz;
  final double maxHz;

  /// Absolute threshold on the CMND (paper suggests 0.1; 0.12 tolerates the
  /// slightly inharmonic attack of plucked strings without octave jumps).
  final double threshold;

  /// Below this RMS (≈ −48 dBFS) the frame is treated as silence.
  final double minRms;

  final int _tauMin;
  final int _tauMax;
  late final Float64List _cmnd;

  /// Samples needed per analysis: W + τmax.
  int get requiredSamples => windowSize + _tauMax;

  /// RMS of [x] over its first [requiredSamples] samples (or all of it).
  double rmsOf(Float32List x) {
    final n = math.min(x.length, requiredSamples);
    if (n == 0) return 0;
    var acc = 0.0;
    for (var i = 0; i < n; i++) {
      acc += x[i] * x[i];
    }
    return math.sqrt(acc / n);
  }

  /// Estimate the fundamental of [x] (mono, −1..1). Returns null for silence
  /// or when no periodicity clears the threshold convincingly.
  PitchEstimate? estimate(Float32List x) {
    if (x.length < requiredSamples) return null;
    final rms = rmsOf(x);
    if (rms < minRms) return null;

    final w = windowSize;
    final tauMax = _tauMax;
    final cmnd = _cmnd;

    // Steps 1–3: difference function with running cumulative mean
    // normalisation. d(τ) = Σ_j (x[j] − x[j+τ])², computed directly; the
    // normalisation divides by the mean of d(1..τ) so d'(τ) sits near 1 for
    // random lags and dips toward 0 at the period.
    cmnd[0] = 1.0;
    var runningSum = 0.0;
    for (var tau = 1; tau <= tauMax; tau++) {
      var d = 0.0;
      for (var j = 0; j < w; j++) {
        final diff = x[j] - x[j + tau];
        d += diff * diff;
      }
      runningSum += d;
      cmnd[tau] = runningSum == 0 ? 1.0 : d * tau / runningSum;
    }

    // Step 4: absolute threshold — the first lag whose CMND dips below the
    // threshold, followed down to its local minimum. Choosing the *first*
    // such dip is what protects against sub-harmonic (octave-down) errors.
    var tau = -1;
    for (var t = _tauMin; t <= tauMax; t++) {
      if (cmnd[t] < threshold) {
        while (t + 1 <= tauMax && cmnd[t + 1] < cmnd[t]) {
          t++;
        }
        tau = t;
        break;
      }
    }
    if (tau < 0) {
      // No dip below the threshold: fall back to the global minimum but only
      // accept it if it is still a clear dip (the note is probably decaying).
      var best = _tauMin;
      for (var t = _tauMin + 1; t <= tauMax; t++) {
        if (cmnd[t] < cmnd[best]) best = t;
      }
      if (cmnd[best] > 0.35) return null;
      tau = best;
    }

    // Step 5: parabolic interpolation around the minimum for sub-sample
    // period accuracy (a cents-level tuner needs it above ~500 Hz).
    var refined = tau.toDouble();
    if (tau > 0 && tau < tauMax) {
      final s0 = cmnd[tau - 1];
      final s1 = cmnd[tau];
      final s2 = cmnd[tau + 1];
      final denom = 2 * (2 * s1 - s2 - s0);
      if (denom.abs() > 1e-12) {
        final shift = (s2 - s0) / denom;
        if (shift.abs() < 1) refined = tau + shift;
      }
    }

    final freq = sampleRate / refined;
    if (!freq.isFinite || freq < minHz || freq > maxHz) return null;
    return PitchEstimate(
      frequency: freq,
      confidence: (1.0 - cmnd[tau]).clamp(0.0, 1.0),
      rms: rms,
    );
  }
}
