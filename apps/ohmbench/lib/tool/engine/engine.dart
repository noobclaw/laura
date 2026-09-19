/// OhmBench's circuit engine: a modified-nodal-analysis solver with a SPICE
/// operating point and a fixed-step transient, in pure Dart with no plugins.
///
/// Nothing here touches the file system, the network or Flutter, which is why
/// `test/engine/` can check every number against a closed form.
library;

export 'linear_system.dart';
export 'netlist.dart';
export 'solver.dart';
