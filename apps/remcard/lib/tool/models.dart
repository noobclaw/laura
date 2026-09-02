import 'dart:math' as math;

import '../core/l10n.dart';

/// The four review grades shown to the user, mapped to SM-2 quality values.
/// Display labels live in the UI layer (study_screen.dart) so they localize.
enum Rating {
  again(1),
  hard(3),
  good(4),
  easy(5);

  const Rating(this.quality);

  /// SM-2 quality score (0..5). Anything < 3 is treated as a lapse.
  final int quality;
}

/// Number of whole days since the Unix epoch for a given local calendar day.
///
/// Built from the local Y/M/D as a UTC date so the count is pure calendar
/// arithmetic: a local-midnight timestamp divided by 86,400,000 is off by one
/// twice a year in zones whose DST switch straddles UTC midnight.
int epochDayOf(DateTime when) =>
    DateTime.utc(when.year, when.month, when.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// Human-scale label for "in N days", shared by the deck list and the grade
/// buttons so the user sees the same number in both places.
String intervalLabel(int days) {
  if (days <= 0) return tr(zh: '今天', en: 'today');
  if (days == 1) return tr(zh: '明天', en: 'tomorrow');
  if (days < 30) return tr(zh: '$days 天', en: '${days}d');
  if (days < 365) {
    final m = (days / 30).round();
    return tr(zh: '$m 个月', en: '${m}mo');
  }
  final y = (days / 365).toStringAsFixed(1).replaceAll('.0', '');
  return tr(zh: '$y 年', en: '${y}y');
}

/// A single flashcard plus its spaced-repetition state.
///
/// The SM-2 fields ([ease], [intervalDays], [repetitions], [dueDay]) are the
/// scheduler's memory. A freshly created card is due immediately.
class Flashcard {
  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    required this.dueDay,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
  });

  final String id;
  String front;
  String back;

  double ease;
  int intervalDays;
  int repetitions;

  /// Epoch day on which this card next becomes due for review.
  int dueDay;

  bool isDue(int today) => dueDay <= today;

  /// Days until this card is next due, relative to [today] (0 = due now).
  int daysUntilDue(int today) => math.max(0, dueDay - today);

  /// The interval [review] would assign for [rating], without mutating —
  /// shown on the grade buttons so the user sees the consequence of each
  /// choice before tapping, the way Anki does.
  ///
  /// Plain SM-2 gives Hard/Good/Easy the same interval and only moves ease,
  /// so a new card graded Easy would still say "tomorrow". The spread below
  /// is Anki's: Easy skips ahead, Hard grows by 1.2 instead of × ease.
  int previewInterval(Rating rating) {
    if (rating == Rating.again) return 1;
    if (repetitions == 0) return rating == Rating.easy ? 4 : 1;
    if (repetitions == 1) return rating == Rating.easy ? 8 : 6;
    final days = switch (rating) {
      Rating.hard => intervalDays * 1.2,
      Rating.easy => intervalDays * ease * 1.3,
      _ => intervalDays * ease,
    };
    return math.max(intervalDays + 1, days.round());
  }

  /// Apply one review with [rating] on the day [today], mutating this card's
  /// schedule per SM-2 with the grade spread described on [previewInterval].
  ///
  /// - Again resets the streak; the study screen re-shows the card in the
  ///   same session, and it is due again tomorrow regardless.
  /// - Otherwise the interval grows: 1 day, then 6 days, then × ease.
  /// - Ease is nudged by the grade and never drops below 1.3.
  void review(Rating rating, int today) {
    final q = rating.quality;
    intervalDays = previewInterval(rating);
    repetitions = q < 3 ? 0 : repetitions + 1;
    // SM-2 ease adjustment.
    ease += 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02);
    if (ease < 1.3) ease = 1.3;
    dueDay = today + intervalDays;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'front': front,
        'back': back,
        'ease': ease,
        'intervalDays': intervalDays,
        'repetitions': repetitions,
        'dueDay': dueDay,
      };

  factory Flashcard.fromJson(Map<String, dynamic> j) => Flashcard(
        id: j['id'] as String,
        front: j['front'] as String? ?? '',
        back: j['back'] as String? ?? '',
        ease: (j['ease'] as num?)?.toDouble() ?? 2.5,
        intervalDays: (j['intervalDays'] as num?)?.toInt() ?? 0,
        repetitions: (j['repetitions'] as num?)?.toInt() ?? 0,
        dueDay: (j['dueDay'] as num?)?.toInt() ?? 0,
      );
}

/// A named collection of cards.
class Deck {
  Deck({required this.id, required this.name, List<Flashcard>? cards})
      : cards = cards ?? [];

  final String id;
  String name;
  final List<Flashcard> cards;

  int dueCount(int today) => cards.where((c) => c.isDue(today)).length;

  List<Flashcard> dueCards(int today) =>
      cards.where((c) => c.isDue(today)).toList(growable: false);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cards': cards.map((c) => c.toJson()).toList(),
      };

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        cards: (j['cards'] as List<dynamic>? ?? [])
            .map((e) => Flashcard.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
