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

  /// Below this the pivot counts as zero and the matrix as singular.
  /// SpiceSharp's `AbsolutePivotThreshold`.
  static const double pivotThreshold = 1e-13;

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

  /// Solves in place and returns the solution, or null when the matrix is
  /// singular (a short across a source, a fully floating island).
  ///
  /// Crout LU with partial pivoting; the system is small enough that the
  /// copy-free in-place factorisation is not worth the extra bookkeeping.
  Float64List? solve() {
    final n = size;
    if (n == 0) return Float64List(0);
    // Row swaps are applied to the right-hand side as they happen, so there
    // is no permutation vector to carry around.
    final a = Float64List.fromList(_a);
    final x = Float64List.fromList(_b);

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
      if (bestValue < pivotThreshold) return null;
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

    for (var row = n - 1; row >= 0; row--) {
      var sum = x[row];
      for (var k = row + 1; k < n; k++) {
        sum -= a[row * n + k] * x[k];
      }
      final diagonal = a[row * n + row];
      if (diagonal.abs() < pivotThreshold) return null;
      x[row] = sum / diagonal;
      if (!x[row].isFinite) return null;
    }
    return x;
  }
}
