import 'package:flutter_test/flutter_test.dart';
import 'package:daycount/tool/models.dart';

void main() {
  final today = DateTime(2026, 7, 18);

  group('daysBetween', () {
    test('future date is positive', () {
      expect(daysBetween(today, DateTime(2026, 7, 20)), 2);
    });
    test('past date is negative', () {
      expect(daysBetween(today, DateTime(2026, 7, 10)), -8);
    });
    test('same day is zero', () {
      expect(daysBetween(today, DateTime(2026, 7, 18)), 0);
    });
    test('ignores time of day', () {
      expect(daysBetween(DateTime(2026, 7, 18, 23), DateTime(2026, 7, 19, 1)), 1);
    });
    test('crosses a DST-style boundary without drift', () {
      // A full month should always be exact whole days.
      expect(daysBetween(DateTime(2026, 3, 1), DateTime(2026, 4, 1)), 31);
    });
  });

  group('clampToMonth', () {
    test('keeps a normal date', () {
      expect(clampToMonth(2026, 6, 14), DateTime(2026, 6, 14));
    });
    test('Feb 29 falls back to Feb 28 in a non-leap year', () {
      expect(clampToMonth(2026, 2, 29), DateTime(2026, 2, 28));
    });
    test('Feb 29 stays in a leap year', () {
      expect(clampToMonth(2028, 2, 29), DateTime(2028, 2, 29));
    });
  });

  group('nextYearlyOccurrence', () {
    test('rolls to next year when already passed this year', () {
      final anchor = DateTime(1990, 3, 5); // birthday
      expect(nextYearlyOccurrence(anchor, today), DateTime(2027, 3, 5));
    });
    test('keeps this year when still upcoming', () {
      final anchor = DateTime(1990, 12, 25);
      expect(nextYearlyOccurrence(anchor, today), DateTime(2026, 12, 25));
    });
    test('today counts as this year (not next)', () {
      final anchor = DateTime(1990, 7, 18);
      expect(nextYearlyOccurrence(anchor, today), DateTime(2026, 7, 18));
    });
  });

  group('statusOf', () {
    test('future countdown', () {
      final e = CountdownEvent(id: '1', title: 'exam', date: DateTime(2026, 7, 28));
      final s = statusOf(e, today);
      expect(s.isFuture, true);
      expect(s.absDays, 10);
    });
    test('past count-up', () {
      final e = CountdownEvent(id: '2', title: 'moved in', date: DateTime(2026, 7, 8));
      final s = statusOf(e, today);
      expect(s.isPast, true);
      expect(s.absDays, 10);
    });
    test('today', () {
      final e = CountdownEvent(id: '3', title: 'now', date: DateTime(2026, 7, 18));
      expect(statusOf(e, today).isToday, true);
    });
    test('yearly event uses the next occurrence', () {
      final e = CountdownEvent(
        id: '4',
        title: 'anniversary',
        date: DateTime(2000, 7, 10),
        yearlyRepeat: true,
      );
      final s = statusOf(e, today);
      // 2027-07-10 is the next occurrence after 2026-07-18.
      expect(s.target, DateTime(2027, 7, 10));
      expect(s.isFuture, true);
    });
  });

  group('sortedEvents', () {
    test('pinned first, then soonest upcoming, then most-recent past', () {
      final pinnedFar =
          CountdownEvent(id: 'p', title: 'pinned', date: DateTime(2026, 12, 1), pinned: true);
      final soon = CountdownEvent(id: 's', title: 'soon', date: DateTime(2026, 7, 20));
      final far = CountdownEvent(id: 'f', title: 'far', date: DateTime(2026, 9, 1));
      final past = CountdownEvent(id: 'x', title: 'past', date: DateTime(2026, 7, 1));

      final sorted = sortedEvents([far, past, soon, pinnedFar], today);
      expect(sorted.map((e) => e.id).toList(), ['p', 's', 'f', 'x']);
    });
  });

  test('event round-trips through JSON', () {
    final e = CountdownEvent(
      id: 'z',
      title: 'trip',
      date: DateTime(2026, 8, 1),
      emoji: '✈️',
      colorValue: 0xFF3E9CE7,
      pinned: true,
      yearlyRepeat: false,
      note: 'Tokyo',
    );
    final back = CountdownEvent.fromJson(e.toJson());
    expect(back.id, e.id);
    expect(back.title, e.title);
    expect(back.date, e.date);
    expect(back.emoji, e.emoji);
    expect(back.colorValue, e.colorValue);
    expect(back.pinned, e.pinned);
    expect(back.note, e.note);
  });
}
