import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:remcard/tool/fsrs.dart';
import 'package:remcard/tool/models.dart';

void main() {
  const fsrs = Fsrs();

  group('forgetting curve', () {
    test('retention is 100% at t=0 and 90% at t=stability', () {
      expect(fsrs.retrievability(10, 0), closeTo(1.0, 1e-9));
      expect(fsrs.retrievability(10, 10), closeTo(0.9, 1e-9));
      expect(fsrs.retrievability(30, 30), closeTo(0.9, 1e-9));
    });

    test('retention decays monotonically with elapsed days', () {
      var prev = 1.0;
      for (var t = 1; t <= 200; t += 7) {
        final r = fsrs.retrievability(20, t);
        expect(r, lessThan(prev));
        prev = r;
      }
      expect(prev, greaterThan(0));
    });

    test('at 90% retention the interval equals stability (SM-2 bridge)', () {
      for (final s in [1.0, 3.0, 12.0, 60.0, 200.0]) {
        expect(fsrs.intervalFor(s), s.round());
      }
    });

    test('interval scales with desired retention', () {
      const relaxed = Fsrs(desiredRetention: 0.8);
      const strict = Fsrs(desiredRetention: 0.95);
      expect(relaxed.intervalFor(100), greaterThan(200));
      expect(strict.intervalFor(100), lessThan(60));
      expect(Fsrs.intervalScale(0.9), closeTo(1, 1e-9));
      expect(Fsrs.intervalScale(0.8), closeTo(2.4, 0.05));
      expect(Fsrs.intervalScale(0.95), closeTo(0.46, 0.02));
    });

    test('interval is clamped to 1..maxIntervalDays', () {
      expect(fsrs.intervalFor(0.1), 1);
      expect(fsrs.intervalFor(0), 1);
      expect(fsrs.intervalFor(5000), Fsrs.defaultMaxInterval);
      expect(const Fsrs(maxIntervalDays: 30).intervalFor(100), 30);
    });
  });

  group('fuzz', () {
    test('leaves short intervals alone', () {
      expect(fsrs.fuzz(1, 7), 1);
      expect(fsrs.fuzz(2, 7), 2);
    });

    test('stays within the documented band and the max interval', () {
      for (var seed = 0; seed < 200; seed++) {
        final f = fsrs.fuzz(10, seed);
        expect(f, inInclusiveRange(9, 11)); // ±(0.15*4.5 + 0.1*3) ≈ ±0.98
        final big = fsrs.fuzz(365, seed);
        expect(big, lessThanOrEqualTo(365));
        expect(big, greaterThanOrEqualTo(340));
      }
    });

    test('is deterministic per seed and monotone in the interval', () {
      expect(fsrs.fuzz(50, 42), fsrs.fuzz(50, 42));
      for (var seed = 0; seed < 50; seed++) {
        var prev = 0;
        for (var d = 3; d <= 120; d++) {
          final f = fsrs.fuzz(d, seed);
          expect(f, greaterThanOrEqualTo(prev), reason: 'seed $seed day $d');
          prev = f;
        }
      }
    });
  });

  group('memory transitions', () {
    test('first grades use the initial stability/difficulty weights', () {
      final again = fsrs.next(null, Rating.again, 0);
      final good = fsrs.next(null, Rating.good, 0);
      final easy = fsrs.next(null, Rating.easy, 0);
      expect(again.stability, closeTo(Fsrs.defaultWeights[0], 1e-9));
      expect(good.stability, closeTo(Fsrs.defaultWeights[2], 1e-9));
      expect(easy.stability, closeTo(Fsrs.defaultWeights[3], 1e-9));
      expect(again.difficulty, greaterThan(good.difficulty));
      expect(good.difficulty, greaterThan(easy.difficulty));
      expect(again.lapses, 1);
      expect(good.lapses, 0);
      expect(good.reps, 1);
    });

    test('Good on schedule keeps growing stability', () {
      var m = fsrs.next(null, Rating.good, 0);
      var prev = m.stability;
      for (var i = 0; i < 8; i++) {
        final ivl = fsrs.intervalFor(m.stability);
        m = fsrs.next(m, Rating.good, ivl);
        expect(m.stability, greaterThan(prev));
        prev = m.stability;
      }
      expect(m.reps, 9);
      expect(fsrs.intervalFor(m.stability), greaterThan(60));
    });

    test('Hard < Good < Easy for the same card', () {
      final m = fsrs.next(null, Rating.good, 0);
      final ivl = fsrs.intervalFor(m.stability);
      final hard = fsrs.next(m, Rating.hard, ivl);
      final good = fsrs.next(m, Rating.good, ivl);
      final easy = fsrs.next(m, Rating.easy, ivl);
      expect(hard.stability, lessThan(good.stability));
      expect(good.stability, lessThan(easy.stability));
      expect(hard.difficulty, greaterThan(good.difficulty));
      expect(good.difficulty, greaterThan(easy.difficulty));
    });

    test('Again collapses stability and counts a lapse', () {
      var m = fsrs.next(null, Rating.good, 0);
      for (var i = 0; i < 5; i++) {
        m = fsrs.next(m, Rating.good, fsrs.intervalFor(m.stability));
      }
      final mature = m.stability;
      final lapsed = fsrs.next(m, Rating.again, fsrs.intervalFor(mature));
      expect(lapsed.stability, lessThan(mature));
      expect(lapsed.stability, lessThan(mature / 3));
      expect(lapsed.lapses, 1);
      expect(lapsed.difficulty, greaterThan(m.difficulty));
      // A same-day Again while relearning is the same lapse, not a new one.
      final relapse = fsrs.next(lapsed, Rating.again, 0);
      expect(relapse.lapses, 1);
      expect(relapse.stability, lessThan(lapsed.stability));
    });

    test('late recall earns a bigger jump than on-time recall', () {
      final m = fsrs.next(null, Rating.good, 0);
      final ivl = fsrs.intervalFor(m.stability);
      final onTime = fsrs.next(m, Rating.good, ivl);
      final late = fsrs.next(m, Rating.good, ivl * 4);
      expect(late.stability, greaterThan(onTime.stability));
    });

    test('same-day relearn uses the short-term formula', () {
      final m = fsrs.next(null, Rating.again, 0);
      final good = fsrs.next(m, Rating.good, 0);
      final easy = fsrs.next(m, Rating.easy, 0);
      expect(good.stability,
          closeTo(fsrs.shortTermStability(m.stability, Rating.good), 1e-9));
      expect(good.stability, greaterThan(m.stability));
      expect(easy.stability, greaterThan(good.stability));
    });

    test('difficulty stays inside 1..10 under extreme grading', () {
      var m = fsrs.next(null, Rating.again, 0);
      for (var i = 0; i < 50; i++) {
        m = fsrs.next(m, Rating.again, 1);
        expect(m.difficulty, inInclusiveRange(1, 10));
      }
      m = fsrs.next(null, Rating.easy, 0);
      for (var i = 0; i < 50; i++) {
        m = fsrs.next(m, Rating.easy, fsrs.intervalFor(m.stability));
        expect(m.difficulty, inInclusiveRange(1, 10));
        expect(m.stability.isFinite, isTrue);
      }
    });
  });

  group('SM-2 migration', () {
    test('ease maps 1.3 → 10, 2.5 → ordinary, high ease → 1', () {
      expect(fsrs.difficultyFromEase(1.3), closeTo(10, 1e-9));
      expect(fsrs.difficultyFromEase(2.5),
          closeTo(fsrs.initialDifficulty(Rating.good), 1e-9));
      expect(fsrs.difficultyFromEase(4.0), 1);
      expect(fsrs.difficultyFromEase(1.0), 10); // below the SM-2 floor
      expect(fsrs.difficultyFromEase(1.9),
          lessThan(fsrs.difficultyFromEase(1.5)));
    });

    test('ease ↔ difficulty round-trips inside the linear band', () {
      for (final e in [1.3, 1.8, 2.2, 2.5, 3.0]) {
        final d = fsrs.difficultyFromEase(e);
        expect(fsrs.easeFromDifficulty(d), closeTo(e, 1e-9));
      }
      expect(fsrs.easeFromDifficulty(10), closeTo(1.3, 1e-9));
    });

    test('an SM-2 card converts without moving its due day', () {
      // Written by 1.1.x: reviewed 3 times, interval 15, due on day 215.
      final card = Flashcard.fromJson({
        'id': 'c',
        'front': 'q',
        'back': 'a',
        'ease': 2.36,
        'intervalDays': 15,
        'repetitions': 3,
        'dueDay': 215,
      });
      expect(card.isNew, isFalse);
      expect(card.dueDay, 215);
      expect(card.stability, 15);
      expect(card.lastReviewDay, 200);
      expect(card.repetitions, 3);
      expect(card.difficulty, closeTo(fsrs.difficultyFromEase(2.36), 1e-9));
      // On its due day the scheduler sees it at ~90% retention and grows it.
      final next = card.previewInterval(Rating.good, 215, fsrs);
      expect(next, greaterThan(15));
    });

    test('an SM-2 card that lapsed and relearned is not "new"', () {
      final card = Flashcard.fromJson({
        'id': 'c',
        'front': 'q',
        'back': 'a',
        'ease': 1.7,
        'intervalDays': 1,
        'repetitions': 0,
        'dueDay': 101,
      });
      expect(card.isNew, isFalse);
      expect(card.repetitions, 1);
      expect(card.stability, 1);
      expect(card.lastReviewDay, 100);
    });

    test('an SM-2 card never reviewed stays new', () {
      final card = Flashcard.fromJson({
        'id': 'c',
        'front': 'q',
        'back': 'a',
        'ease': 2.5,
        'intervalDays': 0,
        'repetitions': 0,
        'dueDay': 100,
      });
      expect(card.isNew, isTrue);
      expect(card.stability, 0);
      expect(card.lastReviewDay, isNull);
      expect(card.dueDay, 100);
    });
  });

  group('json', () {
    test('round-trips the FSRS fields and keeps legacy keys', () {
      final c = Flashcard(id: 'c1', front: 'q', back: 'a', dueDay: 0);
      c.review(Rating.good, 100, fsrs);
      c.review(Rating.easy, 100 + c.intervalDays, fsrs);
      c.review(Rating.again, c.dueDay, fsrs);
      final j = c.toJson();
      for (final key in [
        'ease',
        'intervalDays',
        'repetitions',
        'dueDay',
        'fsrs',
        'stability',
        'difficulty',
        'lapses',
        'lastReviewDay',
      ]) {
        expect(j.containsKey(key), isTrue, reason: key);
      }
      expect(j['fsrs'], 1);
      expect(j['intervalDays'], j['dueDay'] - j['lastReviewDay']);
      final back = Flashcard.fromJson(j);
      expect(back.stability, c.stability);
      expect(back.difficulty, c.difficulty);
      expect(back.repetitions, c.repetitions);
      expect(back.lapses, 1);
      expect(back.lastReviewDay, c.lastReviewDay);
      expect(back.dueDay, c.dueDay);
      expect(back.ease, c.ease);
      expect(back.intervalDays, c.intervalDays);
      // Same state → same preview (fuzz seed is state-derived, not random).
      final day = c.dueDay;
      expect(back.previewInterval(Rating.good, day, fsrs),
          c.previewInterval(Rating.good, day, fsrs));
    });

    test('legacy ease written back tracks difficulty', () {
      final easy = Flashcard(id: 'e', front: 'q', back: 'a', dueDay: 0);
      final hard = Flashcard(id: 'h', front: 'q', back: 'a', dueDay: 0);
      easy.review(Rating.easy, 100, fsrs);
      hard.review(Rating.hard, 100, fsrs);
      expect(easy.ease, greaterThan(hard.ease));
      expect(hard.ease, greaterThanOrEqualTo(1.3));
      expect(easy.toJson()['ease'], easy.ease);
    });

    test('FSRS keys win over stale SM-2 keys when both are present', () {
      final card = Flashcard.fromJson({
        'id': 'c',
        'front': 'q',
        'back': 'a',
        'ease': 2.5,
        'intervalDays': 4,
        'repetitions': 2,
        'dueDay': 104,
        'stability': 4.4,
        'difficulty': 6.2,
        'lapses': 1,
        'lastReviewDay': 100,
      });
      expect(card.stability, 4.4);
      expect(card.difficulty, 6.2);
      expect(card.lapses, 1);
      expect(card.lastReviewDay, 100);
    });
  });

  test('the default weights are FSRS-5 (19 parameters, all positive)', () {
    expect(Fsrs.defaultWeights.length, 19);
    expect(Fsrs.defaultWeights.every((w) => w > 0), isTrue);
    expect(Fsrs.defaultWeights.reduce(math.max), closeTo(15.69105, 1e-9));
  });
}
