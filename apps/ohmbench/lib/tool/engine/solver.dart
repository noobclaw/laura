import 'dart:math' as math;
import 'dart:typed_data';

import 'linear_system.dart';
import 'netlist.dart';

/// Tolerances and iteration limits. The defaults are SPICE's, which is the
/// point: a user who checks our answer against LTspice on the desktop should
/// see the same numbers, not "close enough for a phone app".
class SolverOptions {
  const SolverOptions({
    this.gmin = 1e-12,
    this.relativeTolerance = 1e-3,
    this.voltageTolerance = 1e-6,
    this.absoluteTolerance = 1e-12,
    this.maxIterations = 100,
    this.gminSteps = 10,
    this.sourceSteps = 10,
    this.ladderOnly = false,
  });

  /// Conductance shunted across every nonlinear junction so a reverse-biased
  /// diode still gives the matrix something to pivot on.
  final double gmin;

  /// `RELTOL` — relative change allowed between two Newton iterations.
  final double relativeTolerance;

  /// `VNTOL` — absolute floor for node voltages.
  final double voltageTolerance;

  /// `ABSTOL` — absolute floor for branch currents.
  final double absoluteTolerance;

  /// `ITL1` — Newton iterations before a solve is abandoned.
  final int maxIterations;

  /// Decades of gmin stepping to try when plain Newton will not converge;
  /// zero skips gmin stepping altogether.
  final int gminSteps;

  /// Steps of source ramping to try when gmin stepping also fails.
  final int sourceSteps;

  /// Skips plain Newton and goes straight to the gmin/source ladder. For
  /// tests and diagnostics only: the ladder is the code path that runs when
  /// a user's circuit is hard, and it must be exercised on circuits that
  /// happen to be easy (2026-09-22 audit: it had zero coverage).
  final bool ladderOnly;
}

/// Why an answer is what it is — the material the UI turns into one honest
/// line instead of a spinner that never stops.
enum SolverNote {
  /// Plain Newton converged (or the circuit was linear).
  direct,

  /// Needed gmin stepping.
  gminStepping,

  /// Needed source stepping.
  sourceStepping,

  /// The circuit had a floating island; the solver tied every node to ground
  /// through 1 Gohm to get an answer. Real circuits do not need this, so the
  /// UI says "there is a dangling part" rather than failing.
  floatingNodesTiedToGround,

  /// Newton ran out of iterations. No numbers are reported.
  didNotConverge,

  /// The matrix stayed singular even with the shunt — a voltage source
  /// shorted by a wire, or two sources of different value in parallel.
  singular,
}

/// A converged (or failed) DC answer.
class OperatingPoint {
  const OperatingPoint({
    required this.converged,
    required this.nodeVoltages,
    required this.deviceCurrents,
    required this.iterations,
    required this.notes,
  });

  final bool converged;

  /// Node name to volts, ground included (always exactly 0).
  final Map<String, double> nodeVoltages;

  /// Device id to amperes, positive flowing anode to cathode.
  final Map<String, double> deviceCurrents;

  final int iterations;
  final Set<SolverNote> notes;

  double voltageAt(String node) => nodeVoltages[node] ?? 0;

  double currentThrough(String deviceId) => deviceCurrents[deviceId] ?? 0;

  /// Voltage across a device, anode minus cathode.
  double voltageAcross(Device d) => voltageAt(d.anode) - voltageAt(d.cathode);
}

/// One transient run: aligned time and value series, ready to be drawn.
class TransientResult {
  TransientResult({
    required this.times,
    required this.nodeVoltages,
    required this.deviceCurrents,
    required this.notes,
    required this.completed,
  });

  final List<double> times;
  final Map<String, List<double>> nodeVoltages;
  final Map<String, List<double>> deviceCurrents;
  final Set<SolverNote> notes;

  /// False when a step failed to converge; the series hold everything solved
  /// up to that point, which is what a scope should keep showing.
  final bool completed;

  int get sampleCount => times.length;

  List<double> voltageSeries(String node) => nodeVoltages[node] ?? const [];

  List<double> currentSeries(String deviceId) =>
      deviceCurrents[deviceId] ?? const [];
}

/// Per-device memory the solver carries between Newton iterations (junction
/// voltages) and between timesteps (reactive history).
class _DeviceState {
  double junctionVoltage = 0;

  /// Diode current and conductance at [junctionVoltage], from the last load —
  /// what the device-level convergence test extrapolates from.
  double junctionCurrent = 0;
  double junctionConductance = 0;

  double previousVoltage = 0;
  double previousCurrent = 0;
}

/// Everything one matrix load needs to know about "when" it is.
class _LoadContext {
  _LoadContext({
    required this.time,
    required this.timeStep,
    required this.backwardEuler,
    required this.gmin,
    required this.sourceFactor,
    required this.shunt,
    required this.firstIteration,
  });

  final double time;

  /// Zero for a DC load: capacitors open, inductors short.
  final double timeStep;

  /// First step of a transient (and any step after a discontinuity) runs
  /// backward Euler, which is what SPICE does — trapezoidal rung on a step
  /// input rings for a few samples.
  final bool backwardEuler;

  final double gmin;

  /// Independent sources are multiplied by this during source stepping.
  final double sourceFactor;

  /// Conductance from every node to ground, normally zero.
  final double shunt;

  /// True on the first Newton iteration, when junctions start at their
  /// critical voltage instead of at whatever the previous solution said.
  bool firstIteration;

  /// The `t = 0` solve of a run started from initial conditions: capacitors
  /// act as voltage sources at their initial voltage, inductors as current
  /// sources at their initial current. SPICE's `uic`.
  bool initialConditions = false;

  /// Set by a load when junction limiting moved any diode away from the
  /// voltage the last solution implied. A limited iteration is never a
  /// converged one (SPICE's `CKTnoncon`): the solution it produced answers a
  /// question the circuit did not ask.
  bool limited = false;
}

/// Modified nodal analysis over a [Netlist].
///
/// Algorithms follow SpiceSharp (MIT, https://github.com/SpiceSharp/SpiceSharp)
/// — junction limiting, the gmin/source stepping ladder and the convergence
/// test are ported from it; see REFERENCE.md for the function-level mapping.
class CircuitSolver {
  CircuitSolver(this.netlist, {this.options = const SolverOptions()}) {
    _buildIndex();
  }

  final Netlist netlist;
  final SolverOptions options;

  final Map<String, int> _nodeIndex = {};
  final List<String> _nodeNames = [];
  final Map<String, int> _branchIndex = {};
  final Map<String, int> _internalNodeIndex = {};
  final Map<String, _DeviceState> _state = {};

  /// Row indices that are node voltages rather than branch currents. Only
  /// these may be tied to ground by the floating-island shunt — putting a
  /// conductance on a branch row would quietly turn an ideal source into a
  /// 1 Gohm one and "solve" a short circuit.
  final Set<int> _voltageRows = {};

  int _size = 0;

  /// Nodes the user named, ground first.
  List<String> get nodeNames => List.unmodifiable(_nodeNames);

  void _buildIndex() {
    _nodeNames.add(kGroundNode);
    _nodeIndex[kGroundNode] = -1;
    for (final device in netlist.devices) {
      for (final node in device.nodes) {
        if (_nodeIndex.containsKey(node)) continue;
        _voltageRows.add(_size);
        _nodeIndex[node] = _size++;
        _nodeNames.add(node);
      }
      // A diode with ohmic resistance needs the internal node SPICE calls
      // posPrime; without series resistance the junction sits on the pin.
      if (device is Diode && device.model.seriesResistance > 0) {
        _voltageRows.add(_size);
        _internalNodeIndex[device.id] = _size++;
      }
      // Voltage sources and inductors always carry a branch current. So do
      // capacitors, whose branch is held at zero except in the `uic` solve —
      // one spare unknown each, in exchange for never rebuilding the matrix.
      if (device is VoltageSource ||
          device is Inductor ||
          device is Capacitor) {
        _branchIndex[device.id] = _size++;
      }
      _state[device.id] = _DeviceState();
    }
  }

  int _indexOf(String node) => _nodeIndex[node] ?? -1;

  int _anodeIndex(Device d) => _indexOf(d.anode);

  int _cathodeIndex(Device d) => _indexOf(d.cathode);

  /// Junction side of a diode: the internal node when it has series
  /// resistance, the pin otherwise.
  int _junctionIndex(Diode d) =>
      _internalNodeIndex[d.id] ?? _indexOf(d.anode);

  // ---------------------------------------------------------------- loading

  void _load(MnaSystem system, _LoadContext ctx, Float64List? solution) {
    system.reset();
    ctx.limited = false;

    if (ctx.shunt > 0) {
      for (final row in _voltageRows) {
        system.addMatrix(row, row, ctx.shunt);
      }
    }

    for (final device in netlist.devices) {
      switch (device) {
        case Resistor r:
          system.stampConductance(
              _anodeIndex(r), _cathodeIndex(r), r.conductance);
        case SwitchDevice s:
          system.stampConductance(
              _anodeIndex(s), _cathodeIndex(s), s.conductance);
        case CurrentSource c:
          final value = _sourceValue(c.waveform, ctx) * ctx.sourceFactor;
          // Current leaves the anode and enters the cathode.
          system.stampCurrentInto(_cathodeIndex(c), _anodeIndex(c), value);
        case VoltageSource v:
          final branch = _branchIndex[v.id]!;
          final value = _sourceValue(v.waveform, ctx) * ctx.sourceFactor;
          _stampBranchVoltage(
              system, _anodeIndex(v), _cathodeIndex(v), branch, value, 0);
        case Capacitor c:
          _loadCapacitor(system, c, ctx);
        case Inductor l:
          _loadInductor(system, l, ctx);
        case Diode d:
          _loadDiode(system, d, ctx, solution);
      }
    }
  }

  /// A source's value at the load's time. The operating point and the
  /// transient's first sample are both `t = 0`, so a sine with a phase starts
  /// where its waveform says instead of stepping from its offset on the
  /// first timestep (2026-09-22, audit P2-11) — ngspice evaluates SIN at
  /// time zero in DC mode for the same reason.
  double _sourceValue(Waveform w, _LoadContext ctx) => w.at(ctx.time);

  /// `v(anode) - v(cathode) - resistance * i = value`, plus the two KCL
  /// entries that push the branch current out of the anode.
  void _stampBranchVoltage(MnaSystem system, int anode, int cathode,
      int branch, double value, double resistance) {
    system.addMatrix(anode, branch, 1);
    system.addMatrix(cathode, branch, -1);
    system.addMatrix(branch, anode, 1);
    system.addMatrix(branch, cathode, -1);
    system.addMatrix(branch, branch, -resistance);
    system.addRhs(branch, value);
  }

  void _loadCapacitor(MnaSystem system, Capacitor c, _LoadContext ctx) {
    final branch = _branchIndex[c.id]!;
    if (ctx.initialConditions) {
      // `uic`: hold the capacitor at its initial voltage and let the branch
      // current be whatever the rest of the circuit demands.
      _stampBranchVoltage(system, _anodeIndex(c), _cathodeIndex(c), branch,
          c.initialVolts ?? 0, 0);
      return;
    }
    // The branch is unused outside the `uic` solve; pin it to zero so the row
    // is not empty.
    system.addMatrix(branch, branch, 1);
    if (ctx.timeStep == 0) {
      // DC: an ideal capacitor is an open circuit. Nothing else to stamp —
      // the shunt (or a resistive path) is what keeps its node solvable.
      return;
    }
    final state = _state[c.id]!;
    final farads = math.max(c.farads, 1e-18);
    final double geq;
    final double ieq;
    if (ctx.backwardEuler) {
      geq = farads / ctx.timeStep;
      ieq = geq * state.previousVoltage;
    } else {
      geq = 2 * farads / ctx.timeStep;
      ieq = geq * state.previousVoltage + state.previousCurrent;
    }
    system.stampConductance(_anodeIndex(c), _cathodeIndex(c), geq);
    system.stampCurrentInto(_anodeIndex(c), _cathodeIndex(c), ieq);
  }

  void _loadInductor(MnaSystem system, Inductor l, _LoadContext ctx) {
    final branch = _branchIndex[l.id]!;
    if (ctx.initialConditions) {
      // `uic`: a current source at the initial current.
      system.addMatrix(_anodeIndex(l), branch, 1);
      system.addMatrix(_cathodeIndex(l), branch, -1);
      system.addMatrix(branch, branch, 1);
      system.addRhs(branch, l.initialAmps ?? 0);
      return;
    }
    if (ctx.timeStep == 0) {
      // DC: a short. v(a) - v(b) = 0 with the branch current free.
      _stampBranchVoltage(
          system, _anodeIndex(l), _cathodeIndex(l), branch, 0, 0);
      return;
    }
    final state = _state[l.id]!;
    final henries = math.max(l.henries, 1e-18);
    final double req;
    final double veq;
    if (ctx.backwardEuler) {
      req = henries / ctx.timeStep;
      veq = -req * state.previousCurrent;
    } else {
      req = 2 * henries / ctx.timeStep;
      veq = -(req * state.previousCurrent + state.previousVoltage);
    }
    _stampBranchVoltage(
        system, _anodeIndex(l), _cathodeIndex(l), branch, veq, req);
  }

  void _loadDiode(
      MnaSystem system, Diode d, _LoadContext ctx, Float64List? solution) {
    final model = d.model;
    final state = _state[d.id]!;
    final vte = model.emissionVoltage;
    final isat = model.saturationCurrent;
    final vcrit = vte * math.log(vte / (math.sqrt2 * isat));
    final junction = _junctionIndex(d);
    final cathode = _cathodeIndex(d);

    double vd;
    if (ctx.firstIteration || solution == null) {
      // SPICE's "junction" initialisation: start every junction just below
      // the knee instead of at zero, which is what keeps a rectifier from
      // needing twenty iterations to leave the flat part of the exponential.
      vd = vcrit;
    } else {
      final raw = _valueOf(solution, junction) - _valueOf(solution, cathode);
      vd = _limitJunction(raw, state.junctionVoltage, vte, vcrit);
      if (vd != raw) ctx.limited = true;
    }
    state.junctionVoltage = vd;

    final double cd;
    final double gd;
    final bv = model.breakdownVoltage;
    if (vd >= -3 * vte) {
      final evd = math.exp(vd / vte);
      cd = isat * (evd - 1) + ctx.gmin * vd;
      gd = isat * evd / vte + ctx.gmin;
    } else if (bv == null || vd >= -bv) {
      var arg = 3 * vte / (vd * math.e);
      arg = arg * arg * arg;
      cd = -isat * (1 + arg) + ctx.gmin * vd;
      gd = isat * 3 * arg / vd + ctx.gmin;
    } else {
      final evrev = math.exp(-(bv + vd) / vte);
      cd = -isat * evrev + ctx.gmin * vd;
      gd = isat * evrev / vte + ctx.gmin;
    }

    state.junctionCurrent = cd;
    state.junctionConductance = gd;

    final cdeq = cd - gd * vd;
    system.stampConductance(junction, cathode, gd);
    system.stampCurrentInto(cathode, junction, cdeq);

    final rs = model.seriesResistance;
    if (rs > 0) {
      system.stampConductance(_anodeIndex(d), junction, 1 / rs);
    }
  }

  /// Limits how far a junction voltage may move in one Newton iteration.
  /// Ported from SpiceSharp's `Semiconductor.LimitJunction`, itself ngspice's
  /// `DEVpnjlim`. Without it `exp(v/Vt)` overflows on the first bad guess and
  /// the whole solve is lost.
  double _limitJunction(
      double newVoltage, double oldVoltage, double vte, double vcrit) {
    var v = newVoltage;
    if (v > vcrit && (v - oldVoltage).abs() > 2 * vte) {
      if (oldVoltage > 0) {
        // The outer test guarantees |v - oldVoltage| > 2*vte, so `arg > 0`
        // implies `arg > 2` and the logarithms below stay real.
        final arg = (v - oldVoltage) / vte;
        if (arg > 0) {
          v = oldVoltage + vte * (2 + math.log(arg - 2));
        } else {
          v = oldVoltage - vte * (2 + math.log(2 - arg));
        }
      } else {
        v = vte * math.log(v / vte);
      }
    } else if (v < 0) {
      final arg = oldVoltage > 0 ? -oldVoltage - 1 : 2 * oldVoltage - 1;
      if (v < arg) v = arg;
    }
    return v;
  }

  double _valueOf(Float64List solution, int index) =>
      index < 0 ? 0 : solution[index];

  // --------------------------------------------------------------- analysis

  /// Newton iterations spent by the last analysis, fallbacks included.
  int _iterationCount = 0;

  /// DC operating point: Newton with the SPICE fallback ladder.
  OperatingPoint operatingPoint() {
    _iterationCount = 0;
    final notes = <SolverNote>{};
    final ctx = _dcContext();
    final attempt = _solveWithFallbacks(ctx, null, notes);
    return _toOperatingPoint(attempt, ctx, notes);
  }

  _LoadContext _dcContext({bool initialConditions = false}) => _LoadContext(
        time: 0,
        timeStep: 0,
        backwardEuler: false,
        gmin: options.gmin,
        sourceFactor: 1,
        shunt: 0,
        firstIteration: true,
      )..initialConditions = initialConditions;

  /// Runs Newton, and when it fails walks the ladder: retry with a shunt to
  /// ground (a dangling part), then gmin stepping, then source stepping.
  Float64List? _solveWithFallbacks(
      _LoadContext ctx, Float64List? start, Set<SolverNote> notes) {
    if (_size == 0) return Float64List(0);

    var base = ctx;
    var shunted = false;
    var lastSingular = false;

    if (!options.ladderOnly) {
      var result = _newton(ctx, start);
      if (result.solution != null) {
        notes.add(SolverNote.direct);
        return result.solution;
      }
      lastSingular = result.singular;

      if (result.singular) {
        // A floating island has no path to the reference node. A shunt to
        // ground turns "no answer" into an answer plus a warning the user can
        // act on. It must be far below every real conductance in the circuit
        // or it changes the answer it is only meant to make possible.
        base = _contextWith(ctx, shunt: _floatingShunt());
        shunted = true;
        result = _newton(base, start);
        if (result.solution != null) {
          notes
            ..add(SolverNote.direct)
            ..add(SolverNote.floatingNodesTiedToGround);
          return result.solution;
        }
        lastSingular = result.singular;
      }
    }

    if (netlist.isNonlinear) {
      // The ladders keep the shunt when the plain solve needed one: a circuit
      // that is both floating and hard to bias would otherwise never solve
      // (audit P2-10).
      // `gminSteps: 0` disables the gmin ladder, as ngspice's
      // `.option gminsteps=0` does.
      if (options.gminSteps > 0) {
        final gmin = _gminStepping(base, start, notes);
        if (gmin.solution != null) {
          if (shunted) notes.add(SolverNote.floatingNodesTiedToGround);
          return gmin.solution;
        }
      }
      final source = _sourceStepping(base, notes);
      if (source.solution != null) {
        if (shunted) notes.add(SolverNote.floatingNodesTiedToGround);
        return source.solution;
      }
      lastSingular = source.singular;
    } else if (options.ladderOnly) {
      final result = _newton(ctx, start);
      if (result.solution != null) {
        notes.add(SolverNote.direct);
        return result.solution;
      }
      lastSingular = result.singular;
    }

    notes.add(lastSingular ? SolverNote.singular : SolverNote.didNotConverge);
    return null;
  }

  /// The floating-island shunt: 1 Gohm, or a millionth of the smallest real
  /// conductance in the circuit when that is smaller still (a 1e14-ohm
  /// divider must not be loaded by a 1e9-ohm tie).
  double _floatingShunt() {
    var smallest = double.infinity;
    for (final device in netlist.devices) {
      final g = switch (device) {
        Resistor r => r.conductance,
        SwitchDevice s => s.conductance,
        _ => double.infinity,
      };
      if (g < smallest) smallest = g;
    }
    return math.max(math.min(1e-9, smallest * 1e-6), 1e-30);
  }

  _LoadContext _contextWith(_LoadContext ctx,
          {double? gmin, double? sourceFactor, double? shunt}) =>
      _LoadContext(
        time: ctx.time,
        timeStep: ctx.timeStep,
        backwardEuler: ctx.backwardEuler,
        gmin: gmin ?? ctx.gmin,
        sourceFactor: sourceFactor ?? ctx.sourceFactor,
        shunt: shunt ?? ctx.shunt,
        firstIteration: true,
      )..initialConditions = ctx.initialConditions;

  /// Ramps gmin down by decades, each solve seeded with the previous answer.
  /// A junction that cannot find its own bias point can nearly always find
  /// one when a milliohm-scale conductance holds the node still first.
  ///
  /// [start] seeds the first level: in a transient that is the previous
  /// timestep, which is a far better guess than the knee voltage.
  _NewtonResult _gminStepping(
      _LoadContext ctx, Float64List? start, Set<SolverNote> notes) {
    var gmin = options.gmin <= 0 ? 1e-12 : options.gmin;
    gmin *= math.pow(10, options.gminSteps).toDouble();
    Float64List? solution = start;
    for (var step = 0; step <= options.gminSteps; step++) {
      final stepped = _contextWith(ctx, gmin: gmin);
      final result = _newton(stepped, solution);
      if (result.solution == null) return result;
      solution = result.solution;
      gmin /= 10;
    }
    final finalResult =
        _newton(_contextWith(ctx, gmin: options.gmin), solution);
    if (finalResult.solution != null) notes.add(SolverNote.gminStepping);
    return finalResult;
  }

  /// Brings the independent sources up from zero. Every nonlinear circuit is
  /// solvable at zero volts; each step starts from the last answer.
  _NewtonResult _sourceStepping(_LoadContext ctx, Set<SolverNote> notes) {
    Float64List? solution;
    var last = const _NewtonResult(null, singular: false, iterations: 0);
    for (var step = 0; step <= options.sourceSteps; step++) {
      final factor = step / options.sourceSteps;
      final stepped = _contextWith(ctx, sourceFactor: factor);
      last = _newton(stepped, solution);
      if (last.solution == null) return last;
      solution = last.solution;
    }
    notes.add(SolverNote.sourceStepping);
    return last;
  }

  _NewtonResult _newton(_LoadContext ctx, Float64List? start) {
    final system = MnaSystem(_size);
    var solution = start == null ? null : Float64List.fromList(start);
    ctx.firstIteration = start == null;
    final limit = netlist.isNonlinear ? options.maxIterations : 1;

    for (var iteration = 1; iteration <= limit; iteration++) {
      _iterationCount++;
      _load(system, ctx, solution);
      final next = system.solve();
      if (next == null) {
        return _NewtonResult(null, singular: true, iterations: iteration);
      }
      final previous = solution;
      solution = next;
      ctx.firstIteration = false;
      if (!netlist.isNonlinear) {
        return _NewtonResult(solution, singular: false, iterations: iteration);
      }
      // Never on the first iteration (SpiceSharp's `iterno != 1`): its
      // `previous` is a seed from another context — the last gmin level, the
      // last timestep — and agreeing with a seed is not convergence. Without
      // this guard the step where a diode snaps on could be accepted after a
      // single linearisation (audit P1-2).
      if (iteration > 1 &&
          previous != null &&
          !ctx.limited &&
          _converged(previous, next) &&
          _devicesConverged(next)) {
        return _NewtonResult(solution, singular: false, iterations: iteration);
      }
    }
    return _NewtonResult(null, singular: false, iterations: limit);
  }

  /// SPICE's per-unknown test: relative change plus an absolute floor, with a
  /// different floor for voltages (VNTOL) and branch currents (ABSTOL).
  bool _converged(Float64List previous, Float64List next) {
    final branches = _branchIndex.values.toSet();
    for (var i = 0; i < _size; i++) {
      final n = next[i];
      final o = previous[i];
      if (!n.isFinite) return false;
      final floor = branches.contains(i)
          ? options.absoluteTolerance
          : options.voltageTolerance;
      final tolerance =
          options.relativeTolerance * math.max(n.abs(), o.abs()) + floor;
      if ((n - o).abs() > tolerance) return false;
    }
    return true;
  }

  /// The diode's own convergence test (ngspice `DIOconvTest`): the current
  /// the linearised model predicts at the new junction voltage must agree
  /// with the current it was linearised at. Node voltages can settle to
  /// within VNTOL while an exponential's current is still moving by far more
  /// than RELTOL — and the current is what the meter shows (audit P1-3).
  bool _devicesConverged(Float64List solution) {
    for (final device in netlist.devices) {
      if (device is! Diode) continue;
      final state = _state[device.id]!;
      final vd = _valueOf(solution, _junctionIndex(device)) -
          _valueOf(solution, _cathodeIndex(device));
      final delta = vd - state.junctionVoltage;
      final cd = state.junctionCurrent;
      final predicted = cd + state.junctionConductance * delta;
      final tolerance =
          options.relativeTolerance * math.max(predicted.abs(), cd.abs()) +
              options.absoluteTolerance;
      if ((predicted - cd).abs() > tolerance) return false;
    }
    return true;
  }

  OperatingPoint _toOperatingPoint(
      Float64List? solution, _LoadContext ctx, Set<SolverNote> notes) {
    if (solution == null) {
      return OperatingPoint(
        converged: false,
        nodeVoltages: const {},
        deviceCurrents: const {},
        iterations: _iterationCount,
        notes: notes,
      );
    }
    return OperatingPoint(
      converged: true,
      nodeVoltages: _nodeVoltages(solution),
      deviceCurrents: _deviceCurrents(solution, ctx),
      iterations: _iterationCount,
      notes: notes,
    );
  }

  Map<String, double> _nodeVoltages(Float64List solution) {
    final out = <String, double>{kGroundNode: 0};
    for (final name in _nodeNames) {
      if (name == kGroundNode) continue;
      out[name] = _valueOf(solution, _indexOf(name));
    }
    return out;
  }

  /// Currents, anode to cathode, recomputed from the converged solution
  /// rather than carried out of the last companion model — so what the meter
  /// shows is what the reported voltages actually imply.
  Map<String, double> _deviceCurrents(Float64List solution, _LoadContext ctx) {
    final out = <String, double>{};
    for (final device in netlist.devices) {
      final va = _valueOf(solution, _anodeIndex(device));
      final vb = _valueOf(solution, _cathodeIndex(device));
      switch (device) {
        case Resistor r:
          out[r.id] = (va - vb) * r.conductance;
        case SwitchDevice s:
          out[s.id] = (va - vb) * s.conductance;
        case CurrentSource c:
          out[c.id] = _sourceValue(c.waveform, ctx) * ctx.sourceFactor;
        case VoltageSource v:
          out[v.id] = _valueOf(solution, _branchIndex[v.id]!);
        case Inductor l:
          out[l.id] = _valueOf(solution, _branchIndex[l.id]!);
        case Capacitor c:
          out[c.id] = ctx.initialConditions
              ? _valueOf(solution, _branchIndex[c.id]!)
              : _capacitorCurrent(c, va - vb, ctx);
        case Diode d:
          final vj = _valueOf(solution, _junctionIndex(d)) - vb;
          out[d.id] = _diodeCurrent(d, vj, ctx.gmin);
      }
    }
    return out;
  }

  double _capacitorCurrent(Capacitor c, double voltage, _LoadContext ctx) {
    if (ctx.timeStep == 0) return 0;
    final state = _state[c.id]!;
    final farads = math.max(c.farads, 1e-18);
    if (ctx.backwardEuler) {
      final geq = farads / ctx.timeStep;
      return geq * voltage - geq * state.previousVoltage;
    }
    final geq = 2 * farads / ctx.timeStep;
    return geq * voltage - (geq * state.previousVoltage + state.previousCurrent);
  }

  double _diodeCurrent(Diode d, double vd, double gmin) {
    final model = d.model;
    final vte = model.emissionVoltage;
    final isat = model.saturationCurrent;
    final bv = model.breakdownVoltage;
    if (vd >= -3 * vte) {
      return isat * (math.exp(vd / vte) - 1) + gmin * vd;
    }
    if (bv == null || vd >= -bv) {
      var arg = 3 * vte / (vd * math.e);
      arg = arg * arg * arg;
      return -isat * (1 + arg) + gmin * vd;
    }
    return -isat * math.exp(-(bv + vd) / vte) + gmin * vd;
  }

  // -------------------------------------------------------------- transient

  /// Fixed-step transient analysis.
  ///
  /// M1 ships a fixed step because it is predictable on a phone: the user
  /// picks a window and gets that many samples, and a slow circuit cannot
  /// silently eat the battery. Local-truncation-error step control (SPICE's
  /// TRTOL) is M2, where stiff circuits and breakpoints arrive.
  TransientResult transient({
    required double stopTime,
    required double timeStep,
    double startTime = 0,
    bool useInitialConditions = false,
  }) {
    final notes = <SolverNote>{};
    final times = <double>[];
    final voltages = <String, List<double>>{
      for (final name in _nodeNames) name: <double>[],
    };
    final currents = <String, List<double>>{
      for (final device in netlist.devices) device.id: <double>[],
    };

    if (timeStep <= 0 || stopTime <= 0) {
      return TransientResult(
        times: times,
        nodeVoltages: voltages,
        deviceCurrents: currents,
        notes: {SolverNote.didNotConverge},
        completed: false,
      );
    }

    // t = 0 is solved, not stepped: either the operating point the circuit
    // was sitting at, or SPICE's `uic` solve with the reactive parts forced
    // to their initial conditions. Getting this sample from a first timestep
    // instead would shift the whole waveform by one step — an error of h/tau,
    // i.e. 1% at 100 steps per time constant, which is exactly the kind of
    // "the app computes it wrong" this engine exists to avoid.
    final startContext = _dcContext(initialConditions: useInitialConditions);
    var solution = _solveWithFallbacks(startContext, null, notes);
    if (solution == null) {
      return TransientResult(
        times: times,
        nodeVoltages: voltages,
        deviceCurrents: currents,
        notes: notes,
        completed: false,
      );
    }
    _record(solution, startContext, 0, startTime, timeStep, times, voltages,
        currents);
    _carryHistory(solution, startContext);

    var time = timeStep;
    var first = true;

    while (time <= stopTime + timeStep * 1e-9) {
      final ctx = _LoadContext(
        time: time,
        timeStep: timeStep,
        backwardEuler: first,
        gmin: options.gmin,
        sourceFactor: 1,
        shunt: 0,
        firstIteration: false,
      );
      final stepped = _solveWithFallbacks(ctx, solution, notes);
      if (stepped == null) {
        return TransientResult(
          times: times,
          nodeVoltages: voltages,
          deviceCurrents: currents,
          notes: notes,
          completed: false,
        );
      }
      solution = stepped;
      _record(solution, ctx, time, startTime, timeStep, times, voltages,
          currents);
      _carryHistory(solution, ctx);

      time += timeStep;
      first = false;
    }

    return TransientResult(
      times: times,
      nodeVoltages: voltages,
      deviceCurrents: currents,
      notes: notes,
      completed: true,
    );
  }

  /// Appends one sample to the series, unless the window has not opened yet.
  void _record(
    Float64List solution,
    _LoadContext ctx,
    double time,
    double startTime,
    double timeStep,
    List<double> times,
    Map<String, List<double>> voltages,
    Map<String, List<double>> currents,
  ) {
    if (time < startTime - timeStep * 1e-9) return;
    times.add(time);
    _nodeVoltages(solution).forEach((node, v) => voltages[node]?.add(v));
    _deviceCurrents(solution, ctx).forEach((id, i) => currents[id]?.add(i));
  }

  /// Moves each reactive device's voltage and current into its history, which
  /// is what the next step's companion model integrates from.
  void _carryHistory(Float64List solution, _LoadContext ctx) {
    final voltages = _nodeVoltages(solution);
    final currents = _deviceCurrents(solution, ctx);
    for (final device in netlist.devices) {
      if (device is! Capacitor && device is! Inductor) continue;
      final state = _state[device.id]!;
      state.previousVoltage =
          (voltages[device.anode] ?? 0) - (voltages[device.cathode] ?? 0);
      state.previousCurrent = currents[device.id] ?? 0;
    }
  }
}

class _NewtonResult {
  const _NewtonResult(this.solution,
      {required this.singular, required this.iterations});

  final Float64List? solution;
  final bool singular;
  final int iterations;
}
