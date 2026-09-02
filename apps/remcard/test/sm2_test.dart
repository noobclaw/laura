import 'package:flutter_test/flutter_test.dart';
import 'package:remcard/tool/models.dart';

Flashcard _fresh() => Flashcard(id: 'c1', front: 'q', back: 'a', dueDay: 0);

void main() {
  const today = 100;

  test('a fresh Good review schedules 1 day out and starts the streak', () {
    final c = _fresh();
    c.review(Rating.good, today);
    expect(c.repetitions, 1);
    expect(c.intervalDays, 1);
    expect(c.dueDay, today + 1);
    expect(c.ease, closeTo(2.5, 1e-9)); // q=4 leaves ease unchanged
  });

  test('second Good review jumps to 6 days', () {
    final c = _fresh();
    c.review(Rating.good, today); // rep 1, interval 1
    c.review(Rating.good, today + 1); // rep 2, interval 6
    expect(c.repetitions, 2);
    expect(c.intervalDays, 6);
    expect(c.dueDay, today + 1 + 6);
  });

  test('third review multiplies interval by ease', () {
    final c = _fresh();
    c.review(Rating.good, today); // interval 1
    c.review(Rating.good, today); // interval 6
    final easeBefore = c.ease;
    c.review(Rating.good, today); // interval 6 * ease
    expect(c.intervalDays, (6 * easeBefore).round());
  });

  test('Again resets repetitions and re-shows tomorrow', () {
    final c = _fresh();
    c.review(Rating.good, today);
    c.review(Rating.good, today);
    c.review(Rating.again, today);
    expect(c.repetitions, 0);
    expect(c.intervalDays, 1);
    expect(c.dueDay, today + 1);
  });

  test('Easy grows ease, repeated Hard shrinks it but never below 1.3', () {
    final easy = _fresh();
    easy.review(Rating.easy, today);
    expect(easy.ease, greaterThan(2.5));

    final hard = _fresh();
    for (var i = 0; i < 20; i++) {
      hard.review(Rating.hard, today + i);
    }
    expect(hard.ease, greaterThanOrEqualTo(1.3));
  });

  test('grades spread: Hard < Good < Easy, and preview never mutates', () {
    final c = _fresh();
    c.review(Rating.good, today);
    c.review(Rating.good, today); // rep 2, interval 6
    final before = c.toJson();
    final hard = c.previewInterval(Rating.hard);
    final good = c.previewInterval(Rating.good);
    final easy = c.previewInterval(Rating.easy);
    expect(c.toJson(), before); // preview is pure
    expect(hard, lessThan(good));
    expect(good, lessThan(easy));
    expect(hard, greaterThan(c.intervalDays)); // always moves forward
    // The mutation matches what was previewed.
    c.review(Rating.easy, today);
    expect(c.intervalDays, easy);
  });

  test('a new card graded Easy is not shown again tomorrow', () {
    final c = _fresh();
    expect(c.previewInterval(Rating.good), 1);
    expect(c.previewInterval(Rating.easy), greaterThan(1));
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
    c.review(Rating.good, today);
    expect(c.isDue(today), isFalse);
    expect(c.isDue(today + 1), isTrue);
  });

  test('json round-trips schedule state', () {
    final c = _fresh();
    c.review(Rating.good, today);
    c.review(Rating.easy, today);
    final back = Flashcard.fromJson(c.toJson());
    expect(back.ease, c.ease);
    expect(back.intervalDays, c.intervalDays);
    expect(back.repetitions, c.repetitions);
    expect(back.dueDay, c.dueDay);
  });
}
