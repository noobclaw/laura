import 'package:flutter_test/flutter_test.dart';
import 'package:clean_alarm/tool/models.dart';
import 'package:clean_alarm/tool/store.dart';

AlarmItem _alarm({
  int hour = 7,
  int minute = 30,
  Set<int>? weekdays,
}) =>
    AlarmItem(
      id: 't',
      notifId: 1,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
    );

void main() {
  group('repeatLabel', () {
    test('empty is one-time', () => expect(repeatLabel({}), '仅一次'));
    test('all seven days', () => expect(repeatLabel(kWeekdaysAll), '每天'));
    test('mon-fri is workdays', () => expect(repeatLabel(kWorkdays), '工作日'));
    test('sat-sun is weekend', () => expect(repeatLabel(kWeekend), '周末'));
    test('custom lists each day in order', () {
      expect(repeatLabel({3, 1}), '周一、周三');
    });
  });

  group('nextTrigger — one-time', () {
    test('later today when time is still ahead', () {
      final now = DateTime(2026, 7, 24, 6, 0); // 06:00
      expect(nextTrigger(_alarm(hour: 7, minute: 30), now),
          DateTime(2026, 7, 24, 7, 30));
    });
    test('rolls to tomorrow when the time already passed today', () {
      final now = DateTime(2026, 7, 24, 8, 0); // 08:00, alarm was 07:30
      expect(nextTrigger(_alarm(hour: 7, minute: 30), now),
          DateTime(2026, 7, 25, 7, 30));
    });
    test('exactly now counts as passed (fires next day)', () {
      final now = DateTime(2026, 7, 24, 7, 30);
      expect(nextTrigger(_alarm(hour: 7, minute: 30), now),
          DateTime(2026, 7, 25, 7, 30));
    });
  });

  group('nextTrigger — repeating', () {
    // 2026-07-24 is a Friday (weekday 5).
    test('today is selected and time ahead → today', () {
      final now = DateTime(2026, 7, 24, 6, 0);
      final a = _alarm(hour: 7, minute: 30, weekdays: {5}); // Fri
      expect(nextTrigger(a, now), DateTime(2026, 7, 24, 7, 30));
    });
    test('today selected but time passed → next week same day', () {
      final now = DateTime(2026, 7, 24, 9, 0);
      final a = _alarm(hour: 7, minute: 30, weekdays: {5}); // Fri only
      expect(nextTrigger(a, now), DateTime(2026, 7, 31, 7, 30));
    });
    test('workdays picks the next weekday morning', () {
      // Friday 09:00 → next workday is Monday.
      final now = DateTime(2026, 7, 24, 9, 0);
      final a = _alarm(hour: 7, minute: 30, weekdays: kWorkdays);
      expect(nextTrigger(a, now), DateTime(2026, 7, 27, 7, 30)); // Mon
    });
    test('weekend from a Friday picks Saturday', () {
      final now = DateTime(2026, 7, 24, 9, 0);
      final a = _alarm(hour: 8, minute: 0, weekdays: kWeekend);
      expect(nextTrigger(a, now), DateTime(2026, 7, 25, 8, 0)); // Sat
    });
    test('every day picks tomorrow when today has passed', () {
      final now = DateTime(2026, 7, 24, 9, 0);
      final a = _alarm(hour: 7, minute: 0, weekdays: kWeekdaysAll);
      expect(nextTrigger(a, now), DateTime(2026, 7, 25, 7, 0));
    });
    test('crosses a month boundary correctly', () {
      // Fri 2026-07-31 21:00, workdays alarm 08:00 → Mon 2026-08-03.
      final now = DateTime(2026, 7, 31, 21, 0);
      final a = _alarm(hour: 8, minute: 0, weekdays: kWorkdays);
      expect(nextTrigger(a, now), DateTime(2026, 8, 3, 8, 0));
    });
  });

  group('formatUntil', () {
    test('sub-minute', () {
      expect(formatUntil(const Duration(seconds: 30)), '不到 1 分钟后响铃');
    });
    test('minutes only', () {
      expect(formatUntil(const Duration(minutes: 45)), '45 分钟后响铃');
    });
    test('hours and minutes', () {
      expect(formatUntil(const Duration(hours: 8, minutes: 20)),
          '8 小时 20 分钟后响铃');
    });
    test('whole hours', () {
      expect(formatUntil(const Duration(hours: 3)), '3 小时后响铃');
    });
    test('multi-day', () {
      expect(formatUntil(const Duration(days: 2, hours: 5)), '2 天 5 小时后响铃');
    });
  });

  test('AlarmItem round-trips through JSON', () {
    final a = AlarmItem(
      id: 'x',
      notifId: 7,
      hour: 6,
      minute: 45,
      label: '吃药',
      weekdays: {1, 3, 5},
      enabled: false,
      soundOn: false,
      vibrate: true,
      snoozeMinutes: 10,
    );
    final back = AlarmItem.fromJson(a.toJson());
    expect(back.id, a.id);
    expect(back.notifId, a.notifId);
    expect(back.hour, a.hour);
    expect(back.minute, a.minute);
    expect(back.label, a.label);
    expect(back.weekdays, a.weekdays);
    expect(back.enabled, a.enabled);
    expect(back.soundOn, a.soundOn);
    expect(back.vibrate, a.vibrate);
    expect(back.snoozeMinutes, a.snoozeMinutes);
  });

  group('AlarmStore', () {
    test('free tier caps at freeLimit alarms', () {
      final s = AlarmStore(); // no scheduler → no plugin calls
      for (var i = 0; i < AlarmStore.freeLimit; i++) {
        s.add(hour: 6 + i, minute: 0);
      }
      expect(s.alarms.length, AlarmStore.freeLimit);
      expect(s.atLimit, isTrue);
    });

    test('Pro removes the cap', () {
      final s = AlarmStore();
      s.unlockPro();
      expect(s.atLimit, isFalse);
    });

    test('add assigns unique notifIds and sorts by time of day', () {
      final s = AlarmStore();
      s.add(hour: 9, minute: 0);
      s.add(hour: 6, minute: 30);
      s.add(hour: 7, minute: 15);
      expect(s.alarms.map((a) => a.hhmm).toList(),
          ['06:30', '07:15', '09:00']);
      final ids = s.alarms.map((a) => a.notifId).toSet();
      expect(ids.length, 3); // all distinct
    });

    test('toggle flips enabled', () {
      final s = AlarmStore();
      final a = s.add(hour: 8, minute: 0);
      expect(a.enabled, isTrue);
      s.toggle(a, false);
      expect(a.enabled, isFalse);
    });
  });
}
