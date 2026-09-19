import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohmbench/tool/engine/engine.dart';

/// Transient analysis against closed-form answers.
///
/// Contract quoted in PLAN.md: with a step of tau/100, trapezoidal
/// integration must stay inside 0.5% of the analytic waveform for first-order
/// circuits, and inside 1% on amplitude and 0.5% on period for a lossless LC.
void main() {
  group('first-order circuits', () {
    test('RC charging follows 1 - exp(-t/RC)', () {
      const r = 1000.0;
      const c = 1e-6;
      const tau = r * c; // 1 ms
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'out', ohms: r),
        const Capacitor(
            id: 'C1', anode: 'out', cathode: '0', farads: c, initialVolts: 0),
      ]);

      final result = CircuitSolver(circuit).transient(
        stopTime: 5 * tau,
        timeStep: tau / 100,
        useInitialConditions: true,
      );

      expect(result.completed, isTrue);
      final times = result.times;
      final vout = result.voltageSeries('out');
      expect(vout.length, times.length);

      var worst = 0.0;
      for (var i = 0; i < times.length; i++) {
        final analytic = 5 * (1 - math.exp(-times[i] / tau));
        worst = math.max(worst, (vout[i] - analytic).abs());
      }
      expect(worst, lessThan(5 * 0.005),
          reason: 'worst absolute error $worst V over a 5 V swing');

      // One time constant in, a capacitor is at 63.2% by definition.
      final atTau = vout[100];
      expect(atTau, closeTo(5 * (1 - math.exp(-1)), 0.02));
    });

    test('an RC starting from the operating point does not move', () {
      const circuit = [
        VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
        Resistor(id: 'R1', anode: 'in', cathode: 'out', ohms: 1000),
        Capacitor(id: 'C1', anode: 'out', cathode: '0', farads: 1e-6),
      ];

      final result = CircuitSolver(Netlist(circuit)).transient(
        stopTime: 5e-3,
        timeStep: 1e-5,
      );

      expect(result.completed, isTrue);
      // The capacitor charged before t = 0, so the whole run sits at 5 V.
      for (final v in result.voltageSeries('out')) {
        expect(v, closeTo(5, 1e-6));
      }
    });

    test('RL current rises with the same time constant', () {
      const r = 100.0;
      const l = 10e-3;
      const tau = l / r; // 100 us
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(2)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'mid', ohms: r),
        const Inductor(
            id: 'L1', anode: 'mid', cathode: '0', henries: l, initialAmps: 0),
      ]);

      final result = CircuitSolver(circuit).transient(
        stopTime: 5 * tau,
        timeStep: tau / 100,
        useInitialConditions: true,
      );

      expect(result.completed, isTrue);
      final current = result.currentSeries('L1');
      var worst = 0.0;
      for (var i = 0; i < result.times.length; i++) {
        final analytic = (2 / r) * (1 - math.exp(-result.times[i] / tau));
        worst = math.max(worst, (current[i] - analytic).abs());
      }
      expect(worst, lessThan((2 / r) * 0.005));
    });

    test('a capacitor discharges through its resistor', () {
      const tau = 1000.0 * 1e-6;
      final circuit = Netlist([
        const Resistor(id: 'R1', anode: 'out', cathode: '0', ohms: 1000),
        const Capacitor(
            id: 'C1', anode: 'out', cathode: '0', farads: 1e-6, initialVolts: 3),
      ]);

      final result = CircuitSolver(circuit).transient(
        stopTime: 3 * tau,
        timeStep: tau / 200,
        useInitialConditions: true,
      );

      expect(result.completed, isTrue);
      final vout = result.voltageSeries('out');
      for (var i = 0; i < result.times.length; i++) {
        expect(vout[i], closeTo(3 * math.exp(-result.times[i] / tau), 0.015));
      }
    });
  });

  group('second-order and nonlinear', () {
    test('an LC tank oscillates at 1/(2*pi*sqrt(LC)) without losing energy',
        () {
      const l = 1e-3;
      const c = 1e-6;
      final period = 2 * math.pi * math.sqrt(l * c); // ~198.7 us
      final circuit = Netlist([
        const Capacitor(
            id: 'C1', anode: 'n1', cathode: '0', farads: c, initialVolts: 1),
        const Inductor(
            id: 'L1', anode: 'n1', cathode: '0', henries: l, initialAmps: 0),
      ]);

      final result = CircuitSolver(circuit).transient(
        stopTime: 3 * period,
        timeStep: period / 400,
        useInitialConditions: true,
      );

      expect(result.completed, isTrue);
      final v = result.voltageSeries('n1');

      // Trapezoidal integration is energy-preserving on an LC tank; a drifting
      // amplitude would mean the companion model is wrong.
      var peak = 0.0;
      for (var i = v.length - 400; i < v.length; i++) {
        peak = math.max(peak, v[i].abs());
      }
      expect(peak, closeTo(1.0, 0.01));

      // Period from the third zero crossing pair.
      final crossings = <double>[];
      for (var i = 1; i < v.length; i++) {
        if (v[i - 1] <= 0 && v[i] > 0) {
          final t0 = result.times[i - 1];
          final t1 = result.times[i];
          crossings.add(t0 + (t1 - t0) * (0 - v[i - 1]) / (v[i] - v[i - 1]));
        }
      }
      expect(crossings.length, greaterThanOrEqualTo(2));
      final measured = crossings[1] - crossings[0];
      expect(measured, closeTo(period, period * 0.005));
    });

    test('half-wave rectifier clips the negative half', () {
      final circuit = Netlist([
        const VoltageSource(
          id: 'V1',
          anode: 'in',
          cathode: '0',
          waveform: SineWaveform(amplitude: 5, frequencyHz: 1000),
        ),
        const Diode(id: 'D1', anode: 'in', cathode: 'out'),
        const Resistor(id: 'R1', anode: 'out', cathode: '0', ohms: 1000),
      ]);

      final result = CircuitSolver(circuit).transient(
        stopTime: 2e-3,
        timeStep: 2e-6,
      );

      expect(result.completed, isTrue);
      final vout = result.voltageSeries('out');
      final vin = result.voltageSeries('in');

      var maxOut = -1e9;
      var minOut = 1e9;
      for (final v in vout) {
        maxOut = math.max(maxOut, v);
        minOut = math.min(minOut, v);
      }
      // Positive peak is the input minus roughly a junction drop; the negative
      // half is blocked down to leakage.
      expect(maxOut, closeTo(5 - 0.7, 0.25));
      expect(minOut, greaterThan(-0.01));

      // Wherever the input is well negative, the output is not following it.
      for (var i = 0; i < vin.length; i++) {
        if (vin[i] < -1) expect(vout[i], greaterThan(-0.01));
      }
    });

    test('a diode clamp holds a driven node below one drop', () {
      final circuit = Netlist([
        const VoltageSource(
          id: 'V1',
          anode: 'in',
          cathode: '0',
          waveform: SineWaveform(amplitude: 5, frequencyHz: 500),
        ),
        const Resistor(id: 'R1', anode: 'in', cathode: 'n1', ohms: 1000),
        const Diode(id: 'D1', anode: 'n1', cathode: '0'),
      ]);

      final result = CircuitSolver(circuit).transient(
        stopTime: 4e-3,
        timeStep: 4e-6,
      );

      expect(result.completed, isTrue);
      for (final v in result.voltageSeries('n1')) {
        expect(v, lessThan(0.85));
      }
    });
  });

  group('transient guard rails', () {
    test('a pulse source steps when it says it will', () {
      const pulse = PulseWaveform(
        initial: 0,
        pulsed: 5,
        delay: 1e-3,
        width: 1e-3,
        period: 4e-3,
      );
      expect(pulse.at(0), 0);
      expect(pulse.at(0.9e-3), 0);
      expect(pulse.at(1.5e-3), 5);
      expect(pulse.at(2.5e-3), 0);
      // Second period.
      expect(pulse.at(5.5e-3), 5);
    });

    test('a nonsense window returns no samples rather than hanging', () {
      final circuit = Netlist([
        const Resistor(id: 'R1', anode: 'a', cathode: '0', ohms: 1000),
      ]);
      final result = CircuitSolver(circuit)
          .transient(stopTime: 1e-3, timeStep: 0);
      expect(result.completed, isFalse);
      expect(result.sampleCount, 0);
    });

    test('startTime skips the settling window but keeps solving it', () {
      const tau = 1e-3;
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'out', ohms: 1000),
        const Capacitor(
            id: 'C1', anode: 'out', cathode: '0', farads: 1e-6, initialVolts: 0),
      ]);

      final result = CircuitSolver(circuit).transient(
        stopTime: 5 * tau,
        timeStep: tau / 50,
        startTime: 4 * tau,
        useInitialConditions: true,
      );

      expect(result.completed, isTrue);
      expect(result.times.first, closeTo(4 * tau, tau / 50));
      // Already settled by the time the window opens.
      expect(result.voltageSeries('out').first, closeTo(5 * (1 - math.exp(-4)), 0.05));
    });
  });
}
