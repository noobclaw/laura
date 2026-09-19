import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohmbench/tool/engine/engine.dart';

/// DC operating point against closed-form answers.
///
/// The thresholds here are the engine's contract, quoted in PLAN.md: a linear
/// DC answer must match the hand calculation to 1e-9 relative, and a diode
/// bias point must match an independently bisected solution of the same
/// Shockley equation to 1e-5 volts — two orders tighter than the band SPICE's
/// own RELTOL (1e-3 of 0.69 V = 690 uV) would permit. Anything looser and
/// "the app computes it wrong", the complaint this whole project exists to
/// answer, would slip through.
void main() {
  group('linear DC', () {
    test('resistive divider splits the source exactly', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(10)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'mid', ohms: 2000),
        const Resistor(id: 'R2', anode: 'mid', cathode: '0', ohms: 3000),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.converged, isTrue);
      expect(op.voltageAt('in'), closeTo(10, 1e-9));
      expect(op.voltageAt('mid'), closeTo(6, 1e-9));
      // 2 mA around the loop; the source's own current is negative because it
      // is delivering, which is the SPICE sign convention.
      expect(op.currentThrough('R1'), closeTo(2e-3, 1e-12));
      expect(op.currentThrough('V1'), closeTo(-2e-3, 1e-12));
    });

    test('parallel resistors and a current source', () {
      // 3 mA into a 1k || 2k pair = 2 V across it.
      final circuit = Netlist([
        const CurrentSource(
            id: 'I1', anode: '0', cathode: 'n1', waveform: DcWaveform(3e-3)),
        const Resistor(id: 'R1', anode: 'n1', cathode: '0', ohms: 1000),
        const Resistor(id: 'R2', anode: 'n1', cathode: '0', ohms: 2000),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.converged, isTrue);
      expect(op.voltageAt('n1'), closeTo(2.0, 1e-9));
      expect(op.currentThrough('R1'), closeTo(2e-3, 1e-12));
      expect(op.currentThrough('R2'), closeTo(1e-3, 1e-12));
    });

    test('Wheatstone bridge: balanced legs leave the bridge arm dead', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'top', cathode: '0', waveform: DcWaveform(5)),
        const Resistor(id: 'R1', anode: 'top', cathode: 'a', ohms: 1000),
        const Resistor(id: 'R2', anode: 'a', cathode: '0', ohms: 2000),
        const Resistor(id: 'R3', anode: 'top', cathode: 'b', ohms: 1500),
        const Resistor(id: 'R4', anode: 'b', cathode: '0', ohms: 3000),
        const Resistor(id: 'Rbridge', anode: 'a', cathode: 'b', ohms: 470),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.converged, isTrue);
      expect(op.voltageAt('a'), closeTo(10 / 3, 1e-9));
      expect(op.voltageAt('b'), closeTo(10 / 3, 1e-9));
      expect(op.currentThrough('Rbridge').abs(), lessThan(1e-12));
    });

    test('series voltage sources stack', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'a', cathode: '0', waveform: DcWaveform(9)),
        const VoltageSource(
            id: 'V2', anode: 'b', cathode: 'a', waveform: DcWaveform(3)),
        const Resistor(id: 'R1', anode: 'b', cathode: '0', ohms: 4000),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.voltageAt('b'), closeTo(12, 1e-9));
      expect(op.currentThrough('R1'), closeTo(3e-3, 1e-12));
    });

    test('an open switch carries nothing, a closed one carries it all', () {
      Netlist build(bool closed) => Netlist([
            const VoltageSource(
                id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
            SwitchDevice(
                id: 'S1', anode: 'in', cathode: 'out', closed: closed),
            const Resistor(id: 'R1', anode: 'out', cathode: '0', ohms: 1000),
          ]);

      final open = CircuitSolver(build(false)).operatingPoint();
      final closed = CircuitSolver(build(true)).operatingPoint();

      expect(open.currentThrough('R1').abs(), lessThan(1e-8));
      expect(closed.currentThrough('R1'), closeTo(5e-3, 1e-6));
      // Flipping the switch never changes the size of the matrix, which is
      // what lets a live simulation keep running across the toggle.
      expect(CircuitSolver(build(false)).nodeNames,
          equals(CircuitSolver(build(true)).nodeNames));
    });
  });

  group('nonlinear DC', () {
    test('diode bias point matches an independently bisected solution', () {
      const source = 5.0;
      const ohms = 1000.0;
      const model = DiodeModel();
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(source)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'a', ohms: ohms),
        const Diode(id: 'D1', anode: 'a', cathode: '0', model: model),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();
      expect(op.converged, isTrue);

      // Independent check: solve (source - vd)/R = Is*(exp(vd/Vte) - 1) by
      // bisection, which shares no code with the Newton solver under test.
      final vte = model.emissionVoltage;
      double residual(double vd) =>
          (source - vd) / ohms -
          model.saturationCurrent * (math.exp(vd / vte) - 1);
      var low = 0.0;
      var high = 1.0;
      for (var i = 0; i < 200; i++) {
        final mid = (low + high) / 2;
        if (residual(mid) > 0) {
          low = mid;
        } else {
          high = mid;
        }
      }
      final expected = (low + high) / 2;

      expect(op.voltageAt('a'), closeTo(expected, 1e-5));
      // A junction current is exponential in its voltage, so the 1e-5 V band
      // above is worth dI/I = dV/Vte = 4e-4 here. Measured: 1.3e-4 relative.
      final expectedCurrent = (source - expected) / ohms;
      expect(op.currentThrough('D1'),
          closeTo(expectedCurrent, expectedCurrent * 1e-3));
    });

    test('a reversed diode blocks, and the answer is not a fake zero', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'a', ohms: 1000),
        const Diode(id: 'D1', anode: '0', cathode: 'a'),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.converged, isTrue);
      // Reverse leakage is saturation current plus gmin — nanoamps, not zero,
      // and the node sits within a hair of the supply.
      expect(op.currentThrough('D1').abs(), lessThan(1e-6));
      expect(op.voltageAt('a'), closeTo(5, 1e-3));
    });

    test('two anti-series diodes still converge (source stepping ladder)', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(12)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'a', ohms: 100),
        const Diode(id: 'D1', anode: 'a', cathode: 'b'),
        const Diode(id: 'D2', anode: 'b', cathode: '0'),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.converged, isTrue);
      // Two junction drops, then the rest across the resistor.
      expect(op.voltageAt('a'), greaterThan(1.0));
      expect(op.voltageAt('a'), lessThan(1.8));
      expect(op.currentThrough('D1'), closeTo(op.currentThrough('D2'), 1e-9));
    });

    test('a diode with series resistance adds its ohmic drop', () {
      const rs = 50.0;
      const source = 5.0;
      const ohms = 1000.0;
      const model = DiodeModel(seriesResistance: rs);
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(source)),
        const Resistor(id: 'R1', anode: 'in', cathode: 'a', ohms: ohms),
        const Diode(id: 'D1', anode: 'a', cathode: '0', model: model),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();
      expect(op.converged, isTrue);

      // Independent check, bisected on the current: for a trial I the
      // junction sits at Vte*ln(I/Is + 1) and the pin at that plus I*Rs, so
      // the loop closes when (source - pin)/R == I.
      final vte = model.emissionVoltage;
      double pinFor(double i) =>
          vte * math.log(i / model.saturationCurrent + 1) + i * rs;
      var low = 0.0;
      var high = source / ohms;
      for (var k = 0; k < 200; k++) {
        final mid = (low + high) / 2;
        if ((source - pinFor(mid)) / ohms > mid) {
          low = mid;
        } else {
          high = mid;
        }
      }
      final current = (low + high) / 2;

      expect(op.currentThrough('D1'), closeTo(current, current * 1e-3));
      expect(op.voltageAt('a'), closeTo(pinFor(current), 1e-5));
    });
  });

  group('circuits that do not have an answer', () {
    test('a dangling part is simulated, and the reason is reported', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'in', cathode: '0', waveform: DcWaveform(5)),
        const Resistor(id: 'R1', anode: 'in', cathode: '0', ohms: 1000),
        // Dropped on the canvas, wired to nothing that reaches ground.
        const Resistor(id: 'R2', anode: 'x', cathode: 'y', ohms: 1000),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.converged, isTrue);
      expect(op.notes, contains(SolverNote.floatingNodesTiedToGround));
      expect(op.voltageAt('in'), closeTo(5, 1e-6));
      expect(op.voltageAt('x').abs(), lessThan(1e-6));
    });

    test('a shorted source reports singular instead of inventing numbers', () {
      final circuit = Netlist([
        const VoltageSource(
            id: 'V1', anode: 'a', cathode: '0', waveform: DcWaveform(5)),
        const VoltageSource(
            id: 'V2', anode: 'a', cathode: '0', waveform: DcWaveform(3)),
      ]);

      final op = CircuitSolver(circuit).operatingPoint();

      expect(op.converged, isFalse);
      expect(op.notes, contains(SolverNote.singular));
      expect(op.nodeVoltages, isEmpty);
    });

    test('an empty canvas is not an error', () {
      final op = CircuitSolver(Netlist([])).operatingPoint();
      expect(op.converged, isTrue);
      expect(op.nodeVoltages[kGroundNode], 0);
    });
  });
}
