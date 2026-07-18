import 'package:flutter/material.dart';

/// A single tracked day: either a countdown to a future date or a count-up
/// since a past date. Anniversaries/birthdays set [yearlyRepeat] so the target
/// rolls forward to the next occurrence automatically.
class CountdownEvent {
  CountdownEvent({
    required this.id,
    required this.title,
    required this.date,
    this.emoji = '📅',
    this.colorValue = 0xFFE7625F,
    this.pinned = false,
    this.yearlyRepeat = false,
    this.note = '',
  });

  final String id;
  String title;

  /// Anchor date (date-only semantics; time part is ignored).
  DateTime date;
  String emoji;
  int colorValue;
  bool pinned;

  /// When true the event repeats every year (birthdays, anniversaries) and the
  /// effective target is the next occurrence on or after today.
  bool yearlyRepeat;
  String note;

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'emoji': emoji,
        'color': colorValue,
        'pinned': pinned,
        'yearly': yearlyRepeat,
        'note': note,
      };

  static CountdownEvent fromJson(Map<String, dynamic> j) => CountdownEvent(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        date: DateTime.parse(j['date'] as String),
        emoji: (j['emoji'] as String?) ?? '📅',
        colorValue: (j['color'] as int?) ?? 0xFFE7625F,
        pinned: (j['pinned'] as bool?) ?? false,
        yearlyRepeat: (j['yearly'] as bool?) ?? false,
        note: (j['note'] as String?) ?? '',
      );
}

/// Strip a [DateTime] to date-only in the local calendar.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole-day difference between two dates, DST-safe (computed in UTC so a
/// clock change never adds/removes an hour that flips the day count).
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Clamp (month, day) into a valid date of [year]. Handles Feb 29 in non-leap
/// years by falling back to the last valid day of that month (Feb 28).
DateTime clampToMonth(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day; // day 0 => last day of month
  return DateTime(year, month, day <= lastDay ? day : lastDay);
}

/// Next yearly occurrence of [anchor]'s month/day on or after [today].
DateTime nextYearlyOccurrence(DateTime anchor, DateTime today) {
  final t = dateOnly(today);
  var candidate = clampToMonth(t.year, anchor.month, anchor.day);
  if (candidate.isBefore(t)) {
    candidate = clampToMonth(t.year + 1, anchor.month, anchor.day);
  }
  return candidate;
}

/// The date the countdown actually points at right now (rolls forward for
/// yearly-repeating events).
DateTime effectiveDate(CountdownEvent e, DateTime today) =>
    e.yearlyRepeat ? nextYearlyOccurrence(e.date, today) : dateOnly(e.date);

/// Computed status of an event relative to [today].
class EventStatus {
  const EventStatus({required this.days, required this.target});

  /// Whole days from today to the effective target. Positive = future,
  /// 0 = today, negative = past.
  final int days;
  final DateTime target;

  bool get isToday => days == 0;
  bool get isFuture => days > 0;
  bool get isPast => days < 0;

  int get absDays => days.abs();
}

EventStatus statusOf(CountdownEvent e, DateTime today) {
  final target = effectiveDate(e, today);
  return EventStatus(days: daysBetween(today, target), target: target);
}

/// Sort key: pinned first, then nearest upcoming (incl. today) ascending, then
/// past events by how recent they are (closest to today first).
int compareEvents(CountdownEvent a, CountdownEvent b, DateTime today) {
  if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
  final sa = statusOf(a, today);
  final sb = statusOf(b, today);
  final aPast = sa.isPast;
  final bPast = sb.isPast;
  if (aPast != bPast) return aPast ? 1 : -1; // upcoming block before past block
  if (aPast) {
    // both past: most recent (days closest to 0, i.e. largest/least-negative) first
    return sb.days.compareTo(sa.days);
  }
  // both upcoming: soonest first
  return sa.days.compareTo(sb.days);
}

/// Sorted copy of [events] for display.
List<CountdownEvent> sortedEvents(List<CountdownEvent> events, DateTime today) {
  final copy = [...events];
  copy.sort((a, b) => compareEvents(a, b, today));
  return copy;
}

/// Accent colors offered in the editor (Pro unlocks the full set).
const List<int> kEventColors = [
  0xFFE7625F, // coral (default / brand)
  0xFFEF8E3E, // orange
  0xFFF2B705, // amber
  0xFF4CAF82, // green
  0xFF3E9CE7, // blue
  0xFF7C6FE0, // violet
  0xFFE06FAE, // pink
  0xFF6D7A8C, // slate
];

/// The first two colors are always free; the rest need Pro.
const int kFreeColorCount = 2;

/// Emoji presets shown in the editor.
const List<String> kEventEmojis = [
  '📅', '🎂', '❤️', '✈️', '🎓', '💼', '🏠', '🎉',
  '💍', '👶', '🩺', '📝', '🏃', '🌟', '🎯', '🎄',
];

/// Localized weekday label for a date (周一 … 周日).
String weekdayLabel(DateTime d) {
  const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return names[(d.weekday - 1) % 7];
}
