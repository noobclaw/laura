import 'package:flutter_test/flutter_test.dart';
import 'package:remcard/tool/fsrs.dart';
import 'package:remcard/tool/models.dart';

/// Reference-fidelity tests for the FSRS-5 scheduler in `lib/tool/fsrs.dart`.
///
/// The golden numbers below are produced by the **reference algorithm**, not
/// by our own implementation. They come from the fsrs-rs scalar functions in
/// `open-spaced-repetition/fsrs-rs` (`src/model_v6.rs`:
/// `stability_after_success_scalar`, `stability_after_failure_scalar`,
/// `stability_short_term_scalar`, `next_difficulty_scalar`,
/// `power_forgetting_curve_scalar`, `next_interval_scalar`), evaluated with our
/// FSRS-5 default weights fed through the same layout FSRS-5 uses inside that
/// crate: the 19 trained weights extended with `w[19] = 0` and
/// `w[20] = FSRS5_DEFAULT_DECAY = 0.5` (`check_and_fill_parameters_fsrs6`),
/// which makes `decay = -0.5`, `factor = 19/81`, and the short-term
/// `pow(s, -w19)` term collapse to 1. See `apps/remcard/REFERENCE.md`.
///
/// Tolerance is 1e-4 on stabilities/difficulties; intervals are exact integers
/// (round then clamp to `1..maxInterval`, matching `next_interval_scalar`
/// followed by `.round().max(1)` in fsrs-rs).
void main() {
  const fsrs = Fsrs(); // desiredRetention 0.9, max 365, FSRS-5 default weights.
  const tol = 1e-4;

  // Intervals in the golden data assume no fuzz (fuzzSeed omitted).
  int ivl(double stability) => fsrs.intervalFor(stability);

  group('reference: initial states (new card, fsrs-rs init_* scalars)', () {
    // init_stability = max(w[grade-1], 0.1); init_difficulty = clamp(w4 -
    // exp(w5*(grade-1)) + 1, 1, 10). Interval at 90% == round(stability).
    final golden = <Rating, ({double s, double d, int ivl})>{
      Rating.again: (s: 0.40255, d: 7.194900, ivl: 1),
      Rating.hard: (s: 1.18385, d: 6.488305, ivl: 1),
      Rating.good: (s: 3.17300, d: 5.282434, ivl: 3),
      Rating.easy: (s: 15.69105, d: 3.224502, ivl: 16),
    };
    golden.forEach((rating, g) {
      test('$rating', () {
        final m = fsrs.next(null, rating, 0);
        expect(m.stability, closeTo(g.s, tol));
        expect(m.difficulty, closeTo(g.d, tol));
        expect(ivl(m.stability), g.ivl);
      });
    });
  });

  group('reference: Good recalled on schedule (success + difficulty drift)', () {
    // Start Good-new, then grade Good with elapsed = the whole-day interval the
    // scheduler just assigned. Golden = stability_after_success_scalar /
    // next_difficulty_scalar chained through next_interval_scalar.
    test('six on-time Good reviews match fsrs-rs', () {
      final golden = <({int e, double s, double d, int ivl})>[
        (e: 3, s: 10.738926, d: 5.272968, ivl: 11),
        (e: 11, s: 34.577624, d: 5.263545, ivl: 35),
        (e: 35, s: 100.748313, d: 5.254165, ivl: 101),
        (e: 101, s: 269.283835, d: 5.244829, ivl: 269),
        (e: 269, s: 669.309326, d: 5.235535, ivl: 365), // clamped to max
      ];
      var m = fsrs.next(null, Rating.good, 0);
      expect(m.stability, closeTo(3.173, tol));
      for (final g in golden) {
        expect(ivl(m.stability), g.e, reason: 'elapsed feed for step');
        m = fsrs.next(m, Rating.good, g.e);
        expect(m.stability, closeTo(g.s, tol), reason: 'S after e=${g.e}');
        expect(m.difficulty, closeTo(g.d, tol), reason: 'D after e=${g.e}');
        expect(ivl(m.stability), g.ivl, reason: 'ivl after e=${g.e}');
      }
    });
  });

  group('reference: rating fan-out from a first Good (elapsed = interval)', () {
    // From Good-new (S=3.173, D=5.282434), elapsed=3 days, grade each button.
    // r = forgetting_curve(3, 3.173).
    test('Hard / Good / Easy match stability_after_success_scalar', () {
      final base = fsrs.next(null, Rating.good, 0);
      const e = 3;
      final hard = fsrs.next(base, Rating.hard, e);
      final good = fsrs.next(base, Rating.good, e);
      final easy = fsrs.next(base, Rating.easy, e);
      expect(hard.stability, closeTo(4.924512, tol));
      expect(hard.difficulty, closeTo(6.034950, tol));
      expect(ivl(hard.stability), 5);
      expect(good.stability, closeTo(10.738926, tol));
      expect(good.difficulty, closeTo(5.272968, tol));
      expect(ivl(good.stability), 11);
      expect(easy.stability, closeTo(25.793605, tol));
      expect(easy.difficulty, closeTo(4.510986, tol));
      expect(ivl(easy.stability), 26);
    });
  });

  group('reference: same-day short-term stability (elapsed = 0)', () {
    // From an Again-new card (S=0.40255), grade again same session.
    // stability_short_term_scalar with w19=0: s * exp(w17*(rating-3+w18)),
    // clamped to >= s for Good/Easy.
    test('Good / Easy / Hard match stability_short_term_scalar', () {
      final base = fsrs.next(null, Rating.again, 0);
      expect(base.stability, closeTo(0.40255, tol));
      expect(fsrs.shortTermStability(base.stability, Rating.good),
          closeTo(0.566698, tol));
      expect(fsrs.shortTermStability(base.stability, Rating.easy),
          closeTo(0.949919, tol));
      expect(fsrs.shortTermStability(base.stability, Rating.hard),
          closeTo(0.338078, tol));
    });
  });

  group('reference: post-lapse stability cap (the fixed discrepancy)', () {
    // stability_after_failure_scalar caps at s / exp(w17*w18), NOT at s.
    // Discriminator: s=2, d=5, recalled very late (elapsed=30) so the raw
    // post-lapse value (~2.0777) exceeds the cap. Reference cap = 1.420685;
    // the old min(raw, s) cap would have returned 2.0.
    test('small-stability late lapse takes the s/exp(w17*w18) cap', () {
      final r = fsrs.retrievability(2.0, 30);
      final s = fsrs.forgetStability(5.0, 2.0, r);
      expect(s, closeTo(1.420685, tol));
      expect(s, lessThan(2.0)); // proves the tighter FSRS-5 cap is in effect
    });

    test('mature-card lapse is unaffected (raw << both caps)', () {
      // s=669.309326, d=5.235535, elapsed=365.
      final r = fsrs.retrievability(669.309326, 365);
      final s = fsrs.forgetStability(5.235535, 669.309326, r);
      expect(s, closeTo(10.827885, tol));
    });
  });

  group('reference: forgetting curve & interval inversion', () {
    // power_forgetting_curve_scalar: (1 + factor*t/s)^decay, factor=19/81.
    test('R at t=1 s=2 matches fsrs-rs test vector shape', () {
      // fsrs-rs test_power_forgetting_curve (FSRS-6 params) checks R(1,2)=0.94..
      // Here with factor=19/81: R(1,2) = (1 + 19/81*0.5)^-0.5.
      expect(fsrs.retrievability(2, 1), closeTo(0.9460590, tol));
      expect(fsrs.retrievability(3, 2), closeTo(0.9299294, tol));
    });
    test('interval inverts the curve back to stability at 90%', () {
      for (final s in [1.0, 5.0, 37.0, 200.0]) {
        expect(ivl(s), s.round());
      }
    });
  });
}
