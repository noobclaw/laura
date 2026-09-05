import 'package:flutter_test/flutter_test.dart';
import 'package:remcard/tool/fsrs.dart';
import 'package:remcard/tool/models.dart';

// Card-level scheduling through Flashcard (the store's view of FSRS). The
// algorithm itself is covered in fsrs_test.dart; this file keeps the
// behavioural contracts the UI relies on: due days move forward, Again
// re-shows the card, previews match what a tap assigns, JSON survives.

Flashcard _fresh() => Flashcard(id: 'c1', front: 'q', back: 'a', dueDay: 0);

void main() {
  const today = 100;
  const fsrs = Fsrs();

  test('a fresh Good review schedules a few days out and starts the count', () {
    final c = _fresh();
    c.review(Rating.good, today, fsrs);
    expect(c.repetitions, 1);
    expect(c.isNew, isFalse);
    expect(c.intervalDays, 3); // FSRS-5 w[2] = 3.17 days
    expect(c.dueDay, today + 3);
    expect(c.lastReviewDay, today);
  });

  test('a fresh Hard review comes back tomorrow, Again the same', () {
    final hard = _fresh()..review(Rating.hard, today, fsrs);
    expect(hard.intervalDays, 1);
    final again = _fresh()..review(Rating.again, today, fsrs);
    expect(again.intervalDays, 1);
    expect(again.lapses, 1);
  });

  test('reviews on the due day keep pushing the card further out', () {
    final c = _fresh();
    c.review(Rating.good, today, fsrs);
    var prev = c.intervalDays;
    for (var i = 0; i < 6; i++) {
      c.review(Rating.good, c.dueDay, fsrs);
      // Grows until it reaches the one-year cap (fuzz may shave a little
      // off the cap itself, so only assert growth below it).
      if (prev < 300) expect(c.intervalDays, greaterThan(prev));
      expect(c.intervalDays, lessThanOrEqualTo(Fsrs.defaultMaxInterval));
      expect(c.dueDay, c.lastReviewDay! + c.intervalDays);
      prev = c.intervalDays;
    }
    expect(c.repetitions, 7);
    expect(c.intervalDays, greaterThan(300)); // ≈ a year after 7 Goods
  });

  test('Again shrinks the interval and is due again within days', () {
    final c = _fresh();
    c.review(Rating.good, today, fsrs);
    c.review(Rating.good, c.dueDay, fsrs);
    c.review(Rating.good, c.dueDay, fsrs);
    final before = c.intervalDays;
    final day = c.dueDay;
    c.review(Rating.again, day, fsrs);
    expect(c.intervalDays, lessThan(before));
    expect(c.intervalDays, inInclusiveRange(1, 7));
    expect(c.dueDay, day + c.intervalDays);
    expect(c.lapses, 1);
    expect(c.repetitions, 4); // reviews are counted, not reset
    expect(c.isNew, isFalse);
  });

  test('relearn in the same session does not add a lapse', () {
    final c = _fresh();
    c.review(Rating.good, today, fsrs);
    final day = c.dueDay;
    c.review(Rating.again, day, fsrs);
    final s = c.stability;
    c.relearn(Rating.again, day, fsrs);
    expect(c.lapses, 1);
    expect(c.stability, lessThan(s));
    c.relearn(Rating.good, day, fsrs);
    expect(c.lapses, 1);
    expect(c.dueDay, greaterThan(day));
    expect(c.previewRelearnInterval(Rating.easy, day, fsrs),
        greaterThanOrEqualTo(c.previewRelearnInterval(Rating.again, day, fsrs)));
  });

  test('Easy lowers difficulty, repeated Hard raises it but stays ≤ 10', () {
    final easy = _fresh()..review(Rating.easy, today, fsrs);
    final good = _fresh()..review(Rating.good, today, fsrs);
    expect(easy.difficulty, lessThan(good.difficulty));
    expect(easy.ease, greaterThan(good.ease));

    final hard = _fresh();
    hard.review(Rating.hard, today, fsrs);
    for (var i = 0; i < 20; i++) {
      hard.review(Rating.hard, hard.dueDay, fsrs);
    }
    expect(hard.difficulty, lessThanOrEqualTo(10));
    expect(hard.ease, greaterThanOrEqualTo(1.3));
  });

  test('grades spread: Hard ≤ Good ≤ Easy, and preview never mutates', () {
    final c = _fresh();
    c.review(Rating.good, today, fsrs);
    c.review(Rating.good, c.dueDay, fsrs);
    final day = c.dueDay;
    final before = c.toJson();
    final hard = c.previewInterval(Rating.hard, day, fsrs);
    final good = c.previewInterval(Rating.good, day, fsrs);
    final easy = c.previewInterval(Rating.easy, day, fsrs);
    expect(c.toJson(), before); // preview is pure
    expect(hard, lessThan(good));
    expect(good, lessThan(easy));
    expect(hard, greaterThanOrEqualTo(1));
    // The mutation matches what was previewed (fuzz is state-seeded).
    c.review(Rating.easy, day, fsrs);
    expect(c.intervalDays, easy);
    expect(c.dueDay, day + easy);
  });

  test('a new card graded Easy is not shown again tomorrow', () {
    final c = _fresh();
    expect(c.previewInterval(Rating.good, today, fsrs), greaterThan(1));
    expect(c.previewInterval(Rating.easy, today, fsrs), greaterThan(7));
  });

  test('desired retention changes the interval for the same grade', () {
    final relaxed = _fresh()
      ..review(Rating.good, today, const Fsrs(desiredRetention: 0.8));
    final strict = _fresh()
      ..review(Rating.good, today, const Fsrs(desiredRetention: 0.95));
    expect(relaxed.intervalDays, greaterThan(strict.intervalDays));
    // Memory state is retention-independent; only the due day differs.
    expect(relaxed.stability, closeTo(strict.stability, 1e-9));
  });

  test('epochDayOf is pure calendar arithmetic', () {
    // Same calendar day at different local times → same epoch day.
    final a = epochDayOf(DateTime(2026, 3, 29, 0, 30));
    final b = epochDayOf(DateTime(2026, 3, 29, 23, 30));
    expect(a, b);
    expect(epochDayOf(DateTime(2026, 3, 30)), a + 1);
    expect(epochDayOf(DateTime(1970, 1, 1)), 0);
  });

  test('intervalLabel scales days → months → years', () {
    expect(intervalLabel(0), isNotEmpty);
    expect(intervalLabel(1), isNot(intervalLabel(2)));
    expect(intervalLabel(29), contains('29'));
    expect(intervalLabel(60), contains('2'));
    expect(intervalLabel(730), contains('2'));
  });

  test('isDue reflects the scheduled day', () {
    final c = _fresh();
    expect(c.isDue(today), isTrue); // due today (dueDay 0 <= 100)
    c.review(Rating.good, today, fsrs);
    expect(c.isDue(today), isFalse);
    expect(c.isDue(c.dueDay), isTrue);
    expect(c.daysUntilDue(today), c.intervalDays);
  });

  test('json round-trips schedule state', () {
    final c = _fresh();
    c.review(Rating.good, today, fsrs);
    c.review(Rating.easy, c.dueDay, fsrs);
    final back = Flashcard.fromJson(c.toJson());
    expect(back.ease, c.ease);
    expect(back.intervalDays, c.intervalDays);
    expect(back.repetitions, c.repetitions);
    expect(back.dueDay, c.dueDay);
    expect(back.stability, c.stability);
    expect(back.difficulty, c.difficulty);
    expect(back.lastReviewDay, c.lastReviewDay);
  });
}
