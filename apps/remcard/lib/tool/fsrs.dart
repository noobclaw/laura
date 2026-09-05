import 'dart:math' as math;

import 'models.dart' show Rating;

/// FSRS (Free Spaced Repetition Scheduler) — the FSRS-5 model with its
/// published default parameters, in pure Dart.
///
/// Reference: open-spaced-repetition, "The Algorithm" wiki page, and the
/// fsrs-rs / py-fsrs implementations (MIT). Anki ships the same model as its
/// default scheduler since 23.10 (opt-in) and enabled it by default later.
///
/// The model keeps two numbers per card:
///
/// * **stability** `S` — days until recall probability falls to 90%;
/// * **difficulty** `D` — 1 (easy) … 10 (hard), how fast `S` grows.
///
/// From them the forgetting curve `R(t) = (1 + F·t/S)^-0.5` (with
/// `F = 19/81`) gives the probability of recall after `t` days, and the next
/// interval is the `t` at which `R` reaches the desired retention. At 90%
/// retention that interval is exactly `S`.
///
/// This class is stateless: [next] takes the previous [FsrsMemory] and
/// returns the new one; interval maths lives in [intervalFor]. Days are
/// whole calendar days because the app schedules at day granularity;
/// same-day reviews (the in-session "Again → try again" loop) use the
/// FSRS-5 short-term formula rather than the forgetting curve.
class Fsrs {
  const Fsrs({
    this.desiredRetention = defaultRetention,
    this.maxIntervalDays = defaultMaxInterval,
    this.weights = defaultWeights,
  })  : assert(desiredRetention > 0 && desiredRetention < 1),
        assert(maxIntervalDays >= 1);

  /// The FSRS-5 default parameter vector `w[0..18]`, trained by the
  /// open-spaced-repetition project on ~700M reviews. Meaning by index:
  /// 0–3 initial stability for Again/Hard/Good/Easy; 4–5 initial difficulty;
  /// 6–7 difficulty update and mean reversion; 8–10 stability growth on
  /// recall; 11–14 stability after a lapse; 15 Hard penalty; 16 Easy bonus;
  /// 17–18 same-day (short-term) stability.
  static const List<double> defaultWeights = [
    0.40255, 1.18385, 3.173, 15.69105, // w0–w3
    7.1949, 0.5345, // w4–w5
    1.4604, 0.0046, // w6–w7
    1.54575, 0.1192, 1.01925, // w8–w10
    1.9395, 0.11, 0.29605, 2.2698, // w11–w14
    0.2315, 2.9898, // w15–w16
    0.51655, 0.6621, // w17–w18
  ];

  static const double defaultRetention = 0.9;
  static const double minRetention = 0.8;
  static const double maxRetention = 0.95;
  static const int defaultMaxInterval = 365;

  static const double _decay = -0.5;

  /// `0.9^(1/decay) - 1` — chosen so that at 90% retention the interval
  /// equals stability, which is what makes "stability = interval" a lossless
  /// conversion from SM-2 (see `Flashcard.fromJson`).
  static const double _factor = 19 / 81;

  /// Probability of recall the user is aiming for on each review. Lower =
  /// fewer reviews, more forgetting; 0.9 is the FSRS default. The Settings
  /// slider clamps to [minRetention]..[maxRetention]: below 0.8 the interval
  /// growth stops being worth the misses, above 0.95 the workload explodes.
  final double desiredRetention;

  /// Hard cap on any scheduled interval, in days.
  final int maxIntervalDays;

  final List<double> weights;

  /// How much longer intervals get at [retention] than at the 90% default
  /// (e.g. ≈2.4 at 80%, ≈0.46 at 95%). Shown next to the Settings slider.
  static double intervalScale(double retention) =>
      (math.pow(retention, 1 / _decay) - 1) /
      (math.pow(defaultRetention, 1 / _decay) - 1);

  /// Recall probability after [elapsedDays] for a card with [stability].
  double retrievability(double stability, int elapsedDays) {
    if (stability <= 0) return 0;
    final t = math.max(0, elapsedDays);
    return math.pow(1 + _factor * t / stability, _decay).toDouble();
  }

  /// Days after which recall of a card with [stability] drops to
  /// [desiredRetention], rounded, clamped to `1..maxIntervalDays`, and
  /// optionally fuzzed (see [fuzz]) so cards created together do not all
  /// fall due on the same day forever.
  ///
  /// [fuzzSeed] must be the same for a preview and the review that follows
  /// it, so the number on the grade button is the number the card gets.
  /// `null` disables fuzz.
  int intervalFor(double stability, {int? fuzzSeed}) {
    if (stability <= 0) return 1;
    final raw =
        stability / _factor * (math.pow(desiredRetention, 1 / _decay) - 1);
    final days = raw.round().clamp(1, maxIntervalDays);
    return fuzzSeed == null ? days : fuzz(days, fuzzSeed);
  }

  /// FSRS's interval fuzz: ±15% under a week, ±10% under 20 days, ±5% beyond,
  /// never below 2 days and never above [maxIntervalDays]. Intervals under
  /// 2.5 days are left alone so "tomorrow" stays "tomorrow".
  ///
  /// The random draw is a function of [seed] only, and the same draw is
  /// applied monotonically, so for one card on one day Hard ≤ Good ≤ Easy
  /// still holds after fuzzing.
  int fuzz(int days, int seed) {
    if (days < 2.5) return days;
    var delta = 0.0;
    for (final (start, end, factor) in _fuzzRanges) {
      delta += factor * math.max(0.0, math.min(days.toDouble(), end) - start);
    }
    final maxIvl = math.min((days + delta).round(), maxIntervalDays);
    final minIvl = math.min(math.max(2, (days - delta).round()), maxIvl);
    final u = math.Random(seed).nextDouble();
    return (minIvl + u * (maxIvl - minIvl + 1)).floor().clamp(minIvl, maxIvl);
  }

  static const List<(double, double, double)> _fuzzRanges = [
    (2.5, 7.0, 0.15),
    (7.0, 20.0, 0.10),
    (20.0, double.infinity, 0.05),
  ];

  // ---- FSRS-5 transition formulas -------------------------------------

  static int _grade(Rating r) => switch (r) {
        Rating.again => 1,
        Rating.hard => 2,
        Rating.good => 3,
        Rating.easy => 4,
      };

  double initialStability(Rating r) =>
      math.max(0.1, weights[_grade(r) - 1]);

  double initialDifficulty(Rating r) => _clampD(
      weights[4] - math.exp(weights[5] * (_grade(r) - 1)) + 1);

  double nextDifficulty(double d, Rating r) {
    final delta = -weights[6] * (_grade(r) - 3);
    final damped = d + delta * (10 - d) / 9; // linear damping (FSRS-5)
    // Mean reversion toward the initial difficulty of an Easy first grade.
    final reverted =
        weights[7] * initialDifficulty(Rating.easy) + (1 - weights[7]) * damped;
    return _clampD(reverted);
  }

  /// Stability after a successful recall at retrievability [r].
  double recallStability(double d, double s, double r, Rating rating) {
    final hardPenalty = rating == Rating.hard ? weights[15] : 1.0;
    final easyBonus = rating == Rating.easy ? weights[16] : 1.0;
    final growth = math.exp(weights[8]) *
        (11 - d) *
        math.pow(s, -weights[9]) *
        (math.exp(weights[10] * (1 - r)) - 1) *
        hardPenalty *
        easyBonus;
    return s * (1 + growth);
  }

  /// Stability after a lapse (Again) at retrievability [r]. Never exceeds
  /// the stability the card had before forgetting.
  double forgetStability(double d, double s, double r) {
    final next = weights[11] *
        math.pow(d, -weights[12]) *
        (math.pow(s + 1, weights[13]) - 1) *
        math.exp(weights[14] * (1 - r));
    return math.min(next, s);
  }

  /// Stability after a same-day review (learning / relearning step).
  double shortTermStability(double s, Rating rating) =>
      s * math.exp(weights[17] * (_grade(rating) - 3 + weights[18]));

  static double _clampD(double d) => d.clamp(1.0, 10.0);

  /// The memory state after grading a card [rating] on a day [elapsedDays]
  /// after its previous review. `null` [prev] means the card has never been
  /// reviewed; `elapsedDays == 0` means it is being re-graded in the same
  /// sitting (the short-term path).
  FsrsMemory next(FsrsMemory? prev, Rating rating, int elapsedDays) {
    if (prev == null || prev.stability <= 0) {
      return FsrsMemory(
        stability: initialStability(rating),
        difficulty: initialDifficulty(rating),
        reps: 1,
        lapses: rating == Rating.again ? 1 : 0,
      );
    }
    final d = nextDifficulty(prev.difficulty, rating);
    final double s;
    if (elapsedDays <= 0) {
      s = shortTermStability(prev.stability, rating);
    } else {
      final r = retrievability(prev.stability, elapsedDays);
      s = rating == Rating.again
          ? forgetStability(prev.difficulty, prev.stability, r)
          : recallStability(prev.difficulty, prev.stability, r, rating);
    }
    return FsrsMemory(
      stability: math.max(0.1, s),
      difficulty: d,
      reps: prev.reps + 1,
      // A same-day Again is the same lapse being practised, not a new one.
      lapses: prev.lapses + (rating == Rating.again && elapsedDays > 0 ? 1 : 0),
    );
  }

  // ---- SM-2 bridge -----------------------------------------------------

  /// Difficulty for a card that only has an SM-2 ease factor.
  ///
  /// Anchored so the SM-2 default (2.5) lands on FSRS's initial difficulty
  /// for a first Good (~5.3): a card the old scheduler thought was ordinary
  /// stays ordinary. Ease 1.3 (the SM-2 floor) maps to 10; a card the old
  /// scheduler pushed up to ease ≈ 3.6 maps to 1. Linear in between.
  double difficultyFromEase(double ease) {
    final ordinary = initialDifficulty(Rating.good);
    final slope = (10 - ordinary) / (2.5 - 1.3);
    return _clampD(10 - (ease - 1.3) * slope);
  }

  /// Inverse of [difficultyFromEase], written back to the JSON `ease` key so
  /// an older app version reading the file still gets sane growth.
  double easeFromDifficulty(double d) {
    final ordinary = initialDifficulty(Rating.good);
    final slope = (10 - ordinary) / (2.5 - 1.3);
    return math.max(1.3, 1.3 + (10 - d) / slope);
  }
}

/// A card's FSRS memory state. Immutable; [Fsrs.next] returns a new one.
class FsrsMemory {
  const FsrsMemory({
    required this.stability,
    required this.difficulty,
    required this.reps,
    required this.lapses,
  });

  /// Days until recall probability falls to 90%. `> 0` once reviewed.
  final double stability;

  /// 1 (easy) … 10 (hard).
  final double difficulty;

  /// Total reviews recorded, including same-day relearn grades.
  final int reps;

  /// Times the card was forgotten on a scheduled review.
  final int lapses;
}
