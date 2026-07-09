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
