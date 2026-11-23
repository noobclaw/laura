import 'dart:typed_data';

/// The `A x = b` system a modified-nodal-analysis load produces, plus an LU
/// solve with partial pivoting.
///
/// Dense on purpose. A phone-sized schematic is tens of nodes, and a dense
/// n^3/3 solve at n = 60 is ~72k flops — far below one frame even at the 60
/// solves per second a live simulation wants. Sparse ordering (SpiceSharp's
/// Markowitz pivoting) is an M3 concern and only if measurements demand it.
class MnaSystem {
  MnaSystem(this.size)
      : _a = Float64List(size * size),
        _b = Float64List(size);

  final int size;
  final Float64List _a;
  final Float64List _b;

  /// A pivot smaller than this fraction of the largest magnitude its column
  /// held *before* elimination counts as zero.
  ///
  /// Relative, not absolute (2026-09-22, audit P0-1). The spike compared the
  /// raw pivot against SpiceSharp's absolute 1e-13, which declared any node
  /// held only by conductances below 1e-13 S "singular": two 1e14-ohm
  /// resistors across 10 V then fell through to the floating-node shunt and
  /// came back as 1e-4 V instead of 5 V, flagged as converged. What makes a
  /// column singular is cancellation — a pivot that elimination reduced to
  /// round-off of the entries it started with — so that is what is measured.
  /// Double round-off is ~1e-16 relative; 1e-12 leaves four decades of margin
  /// before a genuinely ill-conditioned column is accepted.
  ///
  /// This intentionally differs from SpiceSharp's `RelativePivotThreshold`
  /// (1e-3), which ranks candidate pivots inside a sparse Markowitz search
  /// rather than deciding singularity; with dense partial pivoting the
  /// chosen pivot is already the column maximum.
  static const double relativePivotThreshold = 1e-12;

  /// Exact-zero guard for a column that was empty to begin with.
  static const double absolutePivotFloor = 1e-300;

  void reset() {
    _a.fillRange(0, _a.length, 0);
    _b.fillRange(0, _b.length, 0);
  }

  double matrix(int row, int col) => _a[row * size + col];

  double rhs(int row) => _b[row];

  /// `A[row][col] += value`, ignoring rows/columns of the ground node, which
  /// carries index -1 and no unknown.
  void addMatrix(int row, int col, double value) {
    if (row < 0 || col < 0) return;
    _a[row * size + col] += value;
  }

  void addRhs(int row, double value) {
    if (row < 0) return;
    _b[row] += value;
  }

  /// Stamps a conductance [g] between the two node indices — the four-corner
  /// pattern every resistive element reduces to.
  void stampConductance(int nodeA, int nodeB, double g) {
    addMatrix(nodeA, nodeA, g);
    addMatrix(nodeB, nodeB, g);
    addMatrix(nodeA, nodeB, -g);
    addMatrix(nodeB, nodeA, -g);
  }

  /// Stamps an independent current [amps] flowing *into* [nodeA] and out of
  /// [nodeB] — the sign convention a Norton companion model produces.
  void stampCurrentInto(int nodeA, int nodeB, double amps) {
    addRhs(nodeA, amps);
    addRhs(nodeB, -amps);
  }

  /// Solves the system and returns the solution, or null when the matrix is
  /// singular (a short across a source, a fully floating island).
  ///
  /// Gaussian elimination with partial pivoting on a copy of the matrix, so
  /// the loaded system stays readable for diagnostics. The copy is n^2
  /// doubles — a few kilobytes at phone scale.
  Float64List? solve() {
    final n = size;
    if (n == 0) return Float64List(0);
    // Row swaps are applied to the right-hand side as they happen, so there
    // is no permutation vector to carry around.
    final a = Float64List.fromList(_a);
    final x = Float64List.fromList(_b);

    // Scale of each column before elimination: the yardstick a pivot is
    // measured against.
    final columnScale = Float64List(n);
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final v = a[row * n + col].abs();
        if (v > columnScale[col]) columnScale[col] = v;
      }
    }

    for (var col = 0; col < n; col++) {
      // Partial pivoting: largest magnitude in the column at or below the
      // diagonal. Without it a leading zero on the diagonal — routine in MNA,
      // where a node touched only by a voltage source has no self-conductance
      // — would divide by zero.
      var best = col;
      var bestValue = a[col * n + col].abs();
      for (var row = col + 1; row < n; row++) {
        final v = a[row * n + col].abs();
        if (v > bestValue) {
          bestValue = v;
          best = row;
        }
      }
      if (bestValue <= absolutePivotFloor ||
          bestValue < columnScale[col] * relativePivotThreshold) {
        return null;
      }
      if (best != col) {
        for (var k = 0; k < n; k++) {
          final tmp = a[col * n + k];
          a[col * n + k] = a[best * n + k];
          a[best * n + k] = tmp;
        }
        final tmp = x[col];
        x[col] = x[best];
        x[best] = tmp;
      }

      final diagonal = a[col * n + col];
      for (var row = col + 1; row < n; row++) {
        final factor = a[row * n + col] / diagonal;
        if (factor == 0) continue;
        a[row * n + col] = 0;
        for (var k = col + 1; k < n; k++) {
          a[row * n + k] -= factor * a[col * n + k];
        }
        x[row] -= factor * x[col];
      }
    }

    // Every diagonal passed the pivot test above; back substitution only has
    // to guard against overflow.
    for (var row = n - 1; row >= 0; row--) {
      var sum = x[row];
      for (var k = row + 1; k < n; k++) {
        sum -= a[row * n + k] * x[k];
      }
      x[row] = sum / a[row * n + row];
      if (!x[row].isFinite) return null;
    }
    return x;
  }
}
