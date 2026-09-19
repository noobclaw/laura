/// The circuit as the solver sees it: two-terminal devices wired to named
/// nodes, with `'0'` reserved for ground.
///
/// This layer is deliberately free of anything Flutter — the editor will own
/// geometry (grid positions, rotation, wire routing) and hand the solver a
/// netlist built from the connectivity it computed. Keeping the two apart is
/// what lets the engine be tested against closed-form answers without a
/// single widget, and what will let the editor be reworked without touching
/// numerics.
library;

import 'dart:math' as math;

/// Ground. Every circuit needs exactly one; the solver treats this node as
/// the reference and never allocates an unknown for it.
const String kGroundNode = '0';

/// Time-varying value of an independent source.
sealed class Waveform {
  const Waveform();

  /// Value at time [t] (seconds). The operating point asks for `t = 0`.
  double at(double t);

  /// The value a DC analysis should use, matching SPICE: the DC level of a
  /// sine, the initial level of a pulse.
  double get dcValue;
}

/// A constant source.
final class DcWaveform extends Waveform {
  const DcWaveform(this.value);

  final double value;

  @override
  double at(double t) => value;

  @override
  double get dcValue => value;
}

/// `offset + amplitude * sin(2*pi*f*t + phase)`, as SPICE's SIN() without the
/// damping term (which M1 does not need).
final class SineWaveform extends Waveform {
  const SineWaveform({
    required this.amplitude,
    required this.frequencyHz,
    this.offset = 0,
    this.phaseDegrees = 0,
  });

  final double amplitude;
  final double frequencyHz;
  final double offset;
  final double phaseDegrees;

  @override
  double at(double t) {
    final phase = phaseDegrees * math.pi / 180.0;
    return offset + amplitude * math.sin(2 * math.pi * frequencyHz * t + phase);
  }

  @override
  double get dcValue => offset;
}

/// A rectangular pulse train, SPICE PULSE(v1 v2 td tr tf pw per).
final class PulseWaveform extends Waveform {
  const PulseWaveform({
    required this.initial,
    required this.pulsed,
    this.delay = 0,
    this.riseTime = 0,
    this.fallTime = 0,
    required this.width,
    required this.period,
  });

  final double initial;
  final double pulsed;
  final double delay;
  final double riseTime;
  final double fallTime;
  final double width;
  final double period;

  @override
  double at(double t) {
    if (t < delay) return initial;
    var local = t - delay;
    if (period > 0) local = local % period;
    if (local < riseTime) {
      return riseTime == 0
          ? pulsed
          : initial + (pulsed - initial) * (local / riseTime);
    }
    if (local < riseTime + width) return pulsed;
    if (local < riseTime + width + fallTime) {
      return fallTime == 0
          ? initial
          : pulsed +
              (initial - pulsed) * ((local - riseTime - width) / fallTime);
    }
    return initial;
  }

  @override
  double get dcValue => initial;
}

/// Shockley diode parameters. Defaults are SPICE's default model card
/// (`.model D D`), which is what every textbook example assumes.
class DiodeModel {
  const DiodeModel({
    this.saturationCurrent = 1e-14,
    this.emissionCoefficient = 1.0,
    this.seriesResistance = 0.0,
    this.breakdownVoltage,
    this.temperatureKelvin = 300.15,
  });

  /// `IS` — saturation current, amperes.
  final double saturationCurrent;

  /// `N` — emission coefficient.
  final double emissionCoefficient;

  /// `RS` — ohmic series resistance. Zero means the junction connects
  /// straight to the terminals and no internal node is allocated.
  final double seriesResistance;

  /// `BV` — reverse breakdown voltage (positive volts), null for none.
  final double? breakdownVoltage;

  /// Junction temperature. SPICE's nominal 27 degrees C.
  final double temperatureKelvin;

  /// Boltzmann's constant over the electron charge, V/K.
  static const double kOverQ = 8.617087e-5;

  /// Thermal voltage kT/q.
  double get thermalVoltage => kOverQ * temperatureKelvin;

  /// `Vte` — thermal voltage scaled by the emission coefficient.
  double get emissionVoltage => emissionCoefficient * thermalVoltage;
}

/// A two-terminal device. Everything M1 needs is two-terminal; transistors
/// (M2) will add a three-terminal sibling rather than widen this.
sealed class Device {
  const Device({required this.id, required this.anode, required this.cathode});

  /// Stable identifier, unique within a netlist (`R1`, `C3`, ...). The editor
  /// keeps the same id across moves and rotations so a running simulation can
  /// follow a device the user is dragging.
  final String id;

  /// Positive terminal. Device current is defined as flowing from [anode]
  /// through the device to [cathode].
  final String anode;

  /// Negative terminal.
  final String cathode;

  List<String> get nodes => [anode, cathode];
}

final class Resistor extends Device {
  const Resistor(
      {required super.id,
      required super.anode,
      required super.cathode,
      required this.ohms});

  final double ohms;
}

/// An ideal independent voltage source. Contributes one branch-current
/// unknown to the system.
final class VoltageSource extends Device {
  const VoltageSource({
    required super.id,
    required super.anode,
    required super.cathode,
    required this.waveform,
  });

  final Waveform waveform;
}

final class CurrentSource extends Device {
  const CurrentSource({
    required super.id,
    required super.anode,
    required super.cathode,
    required this.waveform,
  });

  final Waveform waveform;
}

final class Capacitor extends Device {
  const Capacitor({
    required super.id,
    required super.anode,
    required super.cathode,
    required this.farads,
    this.initialVolts,
  });

  final double farads;

  /// Initial condition used when the analysis starts from `uic`; ignored when
  /// the transient starts from the operating point.
  final double? initialVolts;
}

final class Inductor extends Device {
  const Inductor({
    required super.id,
    required super.anode,
    required super.cathode,
    required this.henries,
    this.initialAmps,
  });

  final double henries;
  final double? initialAmps;
}

final class Diode extends Device {
  const Diode({
    required super.id,
    required super.anode,
    required super.cathode,
    this.model = const DiodeModel(),
  });

  final DiodeModel model;
}

/// A mechanical switch. Modelled as a conductance so that flipping it during
/// a running simulation never changes the shape of the matrix — the reason
/// `iCircuit`-style "always simulating" behaviour is cheap for us.
final class SwitchDevice extends Device {
  const SwitchDevice({
    required super.id,
    required super.anode,
    required super.cathode,
    required this.closed,
    this.onResistance = 1e-3,
    this.offResistance = 1e12,
  });

  final bool closed;
  final double onResistance;
  final double offResistance;

  double get ohms => closed ? onResistance : offResistance;
}

/// A complete circuit.
class Netlist {
  Netlist(this.devices);

  final List<Device> devices;

  /// Every node mentioned by a device, ground included.
  Set<String> get nodeNames => {
        for (final d in devices) ...d.nodes,
      };

  /// True when at least one device is nonlinear, i.e. the operating point
  /// needs Newton iteration rather than a single solve.
  bool get isNonlinear => devices.any((d) => d is Diode);
}
