import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohmbench/tool/engine/engine.dart';

/// Regressions for the 2026-09-19 G2 audit (apps/ohmbench/AUDIT-G2.md).
/// Every test here failed, or passed for the wrong reason, on the spike.
void main() {
  group('P0-1: tiny conductances are real, not singular', () {
    test('a 1e14-ohm divider still splits 10 V in half', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(10)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'mid', ohms: 1e14),
        const Resistor(id: 'R2', anode: 'mid', cathode: '0', ohms: 1e14),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.converged, isTrue);
      expect(op.voltageAt('mid'), closeTo(5, 1e-9));
      // No shunt was needed, so no warning either.
      expect(op.notes, isNot(contains(SolverNote.floatingNodesTiedToGround)));
    });

    test('a 1 fF capacitor at a 10 ms step still follows its source', () {
      // geq = C/h = 1e-13 S: the spike's absolute pivot test called this
      // singular and drew a flat line.
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1',
            anode: 'in',
            cathode: '0',
            waveform: SineWaveform(amplitude: 1, frequencyHz: 5)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'out', ohms: 1000),
        const Capacitor(id: 'C1', anode: 'out', cathode: '0', farads: 1e-15),
      ]);

      final result =
          CircuitSolver(circuit).transient(stopTime: 0.2, timeStep: 0.01);

      expect(result.completed, isTrue);
      final out = result.voltageSeries('out');
      final peak = out.map((v) => v.abs()).reduce(math.max);
      expect(peak, greaterThan(0.9), reason: 'tau = 1 ps, so out == in');
    });

    test('a genuinely floating island is still caught and reported', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
        const Resistor(id: 'R1', anode: 'in', cathode: '0', ohms: 1000),
        const Resistor(id: 'R2', anode: 'x', cathode: 'y', ohms: 1000),
        const Resistor(id: 'R3', anode: 'y', cathode: 'x', ohms: 2000),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.converged, isTrue);
      expect(op.notes, contains(SolverNote.floatingNodesTiedToGround));
      expect(op.voltageAt('in'), closeTo(5, 1e-9));
    });
  });

  group('P1-2/P1-3: convergence means the answer is self-consistent', () {
    test('diode voltages and currents obey KCL at the reported point', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'a', ohms: 1000),
        const Diode(id: 'D1', anode: 'a', cathode: '0'),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.converged, isTrue);
      final resistorCurrent = (5 - op.voltageAt('a')) / 1000;
      // RELTOL is 1e-3; the spike could be off by far more when limiting
      // was active on the accepted iteration.
      expect(op.currentThrough('D1'),
          closeTo(resistorCurrent, resistorCurrent.abs() * 1e-3));
      expect(op.iterations, greaterThan(1),
          reason: 'a nonlinear solve cannot converge on its first pass');
    });

    test('every transient step of a rectifier satisfies KCL', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1',
            anode: 'in',
            cathode: '0',
            waveform: SineWaveform(amplitude: 10, frequencyHz: 50)),
        const Diode(id: 'D1', anode: 'in', cathode: 'out'),
        const Resistor(id: 'R1', anode: 'out', cathode: '0', ohms: 1000),
      ]);

      final result =
          CircuitSolver(circuit).transient(stopTime: 0.04, timeStep: 2e-5);

      expect(result.completed, isTrue);
      final out = result.voltageSeries('out');
      final diode = result.currentSeries('D1');
      var worst = 0.0;
      for (var i = 0; i < out.length; i++) {
        final iR = out[i] / 1000;
        final scale = math.max(iR.abs(), 1e-6);
        worst = math.max(worst, (diode[i] - iR).abs() / scale);
      }
      expect(worst, lessThan(2e-3));
    });
  });

  group('P1-4: a zero-ohm resistor reads what it carries', () {
    test('two resistors in series show the same current', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
        const Resistor(id: 'R0', anode: 'in', cathode: 'a', ohms: 0),
        const Resistor(id: 'R1', anode: 'a', cathode: '0', ohms: 1000),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.converged, isTrue);
      expect(op.currentThrough('R1'), closeTo(5e-3, 1e-9));
      expect(op.currentThrough('R0'),
          closeTo(op.currentThrough('R1'), 1e-9));
    });

    test('a switch with zero on-resistance does not stamp infinity', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
        const SwitchDevice(
            id: 'S1', anode: 'in', cathode: 'a', closed: true, onResistance: 0),
        const Resistor(id: 'R1', anode: 'a', cathode: '0', ohms: 1000),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.converged, isTrue);
      expect(op.currentThrough('S1'), closeTo(5e-3, 1e-9));
    });
  });

  group('the fallback ladder actually runs', () {
    const forward = [
      VoltageSource(id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
      Resistor(id: 'R1', anode: 'in', cathode: 'a', ohms: 1000),
      Diode(id: 'D1', anode: 'a', cathode: '0'),
    ];

    test('gmin stepping reaches the same bias point as plain Newton', () {
      final direct = CircuitSolver(Netlist(forward)).operatingPoint();
      final laddered = CircuitSolver(Netlist(forward),
              options: const SolverOptions(ladderOnly: true))
          .operatingPoint();

      expect(laddered.converged, isTrue);
      expect(laddered.notes, contains(SolverNote.gminStepping));
      expect(laddered.voltageAt('a'), closeTo(direct.voltageAt('a'), 1e-5));
    });

    test('source stepping takes over when gmin stepping cannot', () {
      // gminSteps: 0 disables the gmin ladder (ngspice semantics), so the
      // answer can only have come from source stepping.
      final laddered = CircuitSolver(Netlist(forward),
              options: const SolverOptions(ladderOnly: true, gminSteps: 0))
          .operatingPoint();
      final direct = CircuitSolver(Netlist(forward)).operatingPoint();

      expect(laddered.converged, isTrue);
      expect(laddered.notes, contains(SolverNote.sourceStepping));
      expect(laddered.voltageAt('a'), closeTo(direct.voltageAt('a'), 1e-4));
    });

    test('out of iterations means no numbers, only a reason', () {
      final op = CircuitSolver(Netlist(forward),
              options: const SolverOptions(
                  maxIterations: 1, gminSteps: 1, sourceSteps: 1))
          .operatingPoint();

      expect(op.converged, isFalse);
      expect(op.notes, contains(SolverNote.didNotConverge));
      expect(op.nodeVoltages, isEmpty);
      expect(op.deviceCurrents, isEmpty);
    });
  });

  group('reported numbers that are not placeholders', () {
    test('a reversed diode leaks exactly Is + gmin*V', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'a', ohms: 1000),
        const Diode(id: 'D1', anode: '0', cathode: 'a'),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      // -(1e-14 + 1e-12 * 5) = -5.01e-12 A. A two-sided band: a fake zero
      // fails it, and so does a sign error.
      expect(op.currentThrough('D1'), closeTo(-5.01e-12, 0.02e-12));
    });

    test('RC charging is trapezoidal-accurate, not merely Euler-accurate', () {
      // Backward Euler alone lands ~9 mV off at h = tau/100 on a 5 V swing;
      // trapezoidal (after its one Euler start-up step) stays under 1 mV.
      const tau = 1e-3;
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'out', ohms: 1000),
        const Capacitor(
            id: 'C1', anode: 'out', cathode: '0', farads: 1e-6, initialVolts: 0),
      ]);

      final result = CircuitSolver(circuit).transient(
          stopTime: 5 * tau, timeStep: tau / 100, useInitialConditions: true);

      var worst = 0.0;
      final out = result.voltageSeries('out');
      for (var i = 0; i < out.length; i++) {
        final analytic = 5 * (1 - math.exp(-result.times[i] / tau));
        worst = math.max(worst, (out[i] - analytic).abs());
      }
      expect(worst, lessThan(1e-3));
    });

    test('a sine with a phase starts where its waveform says', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1',
            anode: 'in',
            cathode: '0',
            waveform:
                SineWaveform(amplitude: 2, frequencyHz: 100, phaseDegrees: 90)),
        const Resistor(id: 'R1', anode: 'in', cathode: '0', ohms: 1000),
      ]);

      final result =
          CircuitSolver(circuit).transient(stopTime: 1e-3, timeStep: 1e-5);

      expect(result.voltageSeries('in').first, closeTo(2, 1e-9));
      expect(result.voltageSeries('in')[1], closeTo(2, 1e-2));
    });

    test('one solver can give an operating point, then a transient', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'a', ohms: 1000),
        const Diode(id: 'D1', anode: 'a', cathode: '0'),
        const Capacitor(id: 'C1', anode: 'a', cathode: '0', farads: 1e-6),
      ]);
      final solver = CircuitSolver(circuit);

      final op = solver.operatingPoint();
      final result = solver.transient(stopTime: 1e-3, timeStep: 1e-5);

      expect(result.completed, isTrue);
      // Started from the operating point, so nothing moves.
      for (final v in result.voltageSeries('a')) {
        expect(v, closeTo(op.voltageAt('a'), 1e-6));
      }
    });
  });
}
