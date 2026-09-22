import 'dart:isolate';
import 'dart:math' as math;

import '../engine/engine.dart';
import '../schematic/document.dart';

/// Why a run did not produce numbers. The editor turns each into one
/// sentence that says what to do next — never a spinner, never a guess.
enum RunProblem {
  /// Nothing to simulate yet.
  empty,

  /// No ground symbol: every voltage would be relative to nothing.
  noGround,

  /// A part has a value the engine cannot use (see [SimRun.build]).
  invalidValues,

  /// The solver gave up: shorted source or no convergence. The notes say
  /// which.
  failed,
}

/// One finished simulation: sampled node voltages and part currents over a
/// time window, plus what the editor needs to animate and colour them.
class SimRun {
  SimRun({
    required this.build,
    required this.times,
    required this.nodeSeries,
    required this.partSeries,
    required this.notes,
    required this.completed,
    required this.timeOffset,
    required this.loopFrom,
    required this.problem,
  }) {
    var v = 0.0;
    for (final series in nodeSeries.values) {
      for (final x in series) {
        if (x.abs() > v) v = x.abs();
      }
    }
    peakVolts = v;
    var i = 0.0;
    for (final series in partSeries.values) {
      for (final x in series) {
        if (x.abs() > i) i = x.abs();
      }
    }
    peakAmps = i;
  }

  final NetlistBuild build;

  /// Seconds since the start of this run (the first sample is 0).
  final List<double> times;
  final Map<String, List<double>> nodeSeries;
  final Map<String, List<double>> partSeries;
  final Set<SolverNote> notes;

  /// False when a step failed part-way; the samples up to it are kept.
  final bool completed;

  /// Absolute circuit time of sample 0 — non-zero when this run continues a
  /// previous one (a switch flipped mid-run).
  final double timeOffset;

  /// Sample index playback loops back to, or null to play once and hold the
  /// last sample. Circuits driven by a sine loop over their settled part so
  /// the scope keeps moving; everything else settles and stays settled.
  final int? loopFrom;

  final RunProblem? problem;

  /// Largest |V| and |I| anywhere in the run: the colour and dot-speed scales
  /// are fixed per run so nothing flickers as the cursor moves.
  late final double peakVolts;
  late final double peakAmps;

  int get length => times.length;

  bool get ok => problem == null && times.isNotEmpty;

  double get window => times.isEmpty ? 0 : times.last;

  double nodeVoltage(String node, int i) {
    if (node == kGroundNode) return 0;
    final s = nodeSeries[node];
    if (s == null || s.isEmpty) return 0;
    return s[i.clamp(0, s.length - 1)];
  }

  double partCurrent(String id, int i) {
    final s = partSeries[id];
    if (s == null || s.isEmpty) return 0;
    return s[i.clamp(0, s.length - 1)];
  }

  /// Node a grid point belongs to, or null for a point that is not a pin or
  /// wire end.
  String? nodeAt(GridPoint p) => build.nodeOfPoint[p];

  /// Voltage across a part, first pin minus last pin.
  double partVoltage(SchematicPart part, int i) {
    final pins = part.pins;
    final a = nodeAt(pins.first);
    final b = nodeAt(pins.last);
    if (a == null || b == null) return 0;
    return nodeVoltage(a, i) - nodeVoltage(b, i);
  }

  /// The state to continue from at sample [i]: capacitor voltages and
  /// inductor currents, keyed by part id.
  (Map<String, double>, Map<String, double>) stateAt(
      SchematicDocument doc, int i) {
    final volts = <String, double>{};
    final amps = <String, double>{};
    for (final part in doc.parts) {
      if (part.kind == PartKind.capacitor) {
        volts[part.id] = partVoltage(part, i);
      } else if (part.kind == PartKind.inductor) {
        amps[part.id] = partCurrent(part.id, i);
      }
    }
    return (volts, amps);
  }

  static SimRun failure(NetlistBuild build, RunProblem problem,
          [Set<SolverNote> notes = const {}]) =>
      SimRun(
        build: build,
        times: const [],
        nodeSeries: const {},
        partSeries: const {},
        notes: notes,
        completed: false,
        timeOffset: 0,
        loopFrom: null,
        problem: problem,
      );
}

/// Samples per run. Enough for a smooth scope trace and smooth colour
/// changes; small enough that a 40-part circuit solves in well under a
/// second on an old phone.
const int kSamplesPerRun = 600;

/// How long a run should cover, from what is in the drawing: three cycles
/// of the slowest sine; five of the slowest RC/RL time constant; four
/// periods of the slowest LC pair; a millisecond for a purely resistive
/// circuit (its answer does not change, the window only paces the dots).
double chooseWindow(SchematicDocument doc) {
  double? slowestSine;
  var resistances = <double>[];
  var capacitances = <double>[];
  var inductances = <double>[];
  for (final p in doc.parts) {
    switch (p.kind) {
      case PartKind.sineSource:
        final f = p.secondaryValue;
        if (f > 0 && f.isFinite) {
          slowestSine = slowestSine == null ? f : math.min(slowestSine, f);
        }
      case PartKind.resistor:
        if (p.value > 0) resistances.add(p.value);
      case PartKind.capacitor:
        if (p.value > 0) capacitances.add(p.value);
      case PartKind.inductor:
        if (p.value > 0) inductances.add(p.value);
      default:
    }
  }
  double window;
  if (slowestSine != null) {
    window = 3 / slowestSine;
  } else if (capacitances.isEmpty && inductances.isEmpty) {
    window = 1e-3;
  } else {
    // Geometric mean: one 10 Mohm bias resistor must not stretch the window
    // of a 1 kohm filter by four decades.
    final r = resistances.isEmpty
        ? 1000.0
        : math.exp(resistances.map(math.log).reduce((a, b) => a + b) /
            resistances.length);
    var tau = 0.0;
    for (final c in capacitances) {
      tau = math.max(tau, r * c);
    }
    for (final l in inductances) {
      tau = math.max(tau, l / r);
    }
    window = 5 * tau;
    if (capacitances.isNotEmpty && inductances.isNotEmpty) {
      final period =
          2 * math.pi * math.sqrt(inductances.reduce(math.max) *
              capacitances.reduce(math.max));
      window = math.max(window, 4 * period);
    }
  }
  return window.clamp(10e-6, 20.0);
}

/// Checks the drawing and, when it can be simulated, runs it off the UI
/// isolate.
///
/// The first run of a drawing starts from rest (capacitors empty, inductors
/// still), SPICE's `uic`, because watching a capacitor charge is the point
/// of a teaching simulator. [initialVolts]/[initialAmps]/[timeOffset]
/// continue from a previous run instead (a switch flipped while running).
Future<SimRun> simulate(
  SchematicDocument doc, {
  Map<String, double> initialVolts = const {},
  Map<String, double> initialAmps = const {},
  double timeOffset = 0,
  double? window,
}) async {
  final build = doc.buildNetlist(
    initialVolts: initialVolts,
    initialAmps: initialAmps,
    timeOffset: timeOffset,
  );
  if (build.netlist.devices.isEmpty && build.invalidPartIds.isEmpty) {
    return SimRun.failure(build, RunProblem.empty);
  }
  if (!build.hasGround) return SimRun.failure(build, RunProblem.noGround);
  if (!build.isRunnable) return SimRun.failure(build, RunProblem.invalidValues);

  final stop = window ?? chooseWindow(doc);
  final step = stop / kSamplesPerRun;
  final netlist = build.netlist;

  final result = await Isolate.run(() => runTransient(netlist, stop, step));
  return _assemble(doc, build, result, timeOffset);
}

/// [simulate] on the calling isolate, for tiny built-in circuits (the
/// library's live preview) where spawning an isolate would cost more than
/// the solve.
SimRun simulateNow(SchematicDocument doc) {
  final build = doc.buildNetlist();
  if (!build.hasGround || !build.isRunnable || build.netlist.devices.isEmpty) {
    return SimRun.failure(build, RunProblem.failed);
  }
  final stop = chooseWindow(doc);
  final result = runTransient(build.netlist, stop, stop / kSamplesPerRun);
  return _assemble(doc, build, result, 0);
}

SimRun _assemble(SchematicDocument doc, NetlistBuild build,
    TransientResult result, double timeOffset) {
  if (result.times.isEmpty) {
    return SimRun.failure(build, RunProblem.failed, result.notes);
  }

  final hasSine = doc.parts.any((p) => p.kind == PartKind.sineSource);
  return SimRun(
    build: build,
    times: result.times,
    nodeSeries: result.nodeVoltages,
    partSeries: result.deviceCurrents,
    notes: result.notes,
    completed: result.completed,
    timeOffset: timeOffset,
    // Skip the first of three cycles: the start-up transient would make the
    // loop jump every time it wraps.
    loopFrom: hasSine && result.completed ? result.times.length ~/ 3 : null,
    problem: null,
  );
}

/// The transient itself, isolate-safe (plain data in, plain data out).
///
/// Starting from rest can be inconsistent — an empty capacitor straight
/// across an ideal source asks the solver for 0 V and 5 V on one node — so
/// when the `uic` start is singular the run falls back to starting from the
/// operating point, which is always consistent, and says nothing: both are
/// correct answers, one is just less animated.
TransientResult runTransient(Netlist netlist, double stop, double step) {
  final fromRest = CircuitSolver(netlist)
      .transient(stopTime: stop, timeStep: step, useInitialConditions: true);
  if (fromRest.times.isNotEmpty) return fromRest;
  return CircuitSolver(netlist).transient(stopTime: stop, timeStep: step);
}
