import 'dart:math' as math;

/// The four review grades shown to the user, mapped to SM-2 quality values.
enum Rating {
  again(1, '重来'),
  hard(3, '困难'),
  good(4, '良好'),
  easy(5, '简单');

  const Rating(this.quality, this.label);

  /// SM-2 quality score (0..5). Anything < 3 is treated as a lapse.
  final int quality;
  final String label;
}

/// Number of whole days since the Unix epoch for a given local moment.
/// Using local midnight keeps "due today" intuitive across time zones.
int epochDayOf(DateTime when) {
  final midnight = DateTime(when.year, when.month, when.day);
  return midnight.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
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

  /// Apply one review with [rating] on the day [today], mutating this card's
  /// schedule per the classic SM-2 algorithm.
  ///
  /// - A grade below 3 (Again) resets the streak and re-shows the card tomorrow.
  /// - Otherwise the interval grows: 1 day, then 6 days, then × ease.
  /// - Ease is nudged by the grade and never drops below 1.3.
  void review(Rating rating, int today) {
    final q = rating.quality;
    if (q < 3) {
      repetitions = 0;
      intervalDays = 1;
    } else {
      if (repetitions == 0) {
        intervalDays = 1;
      } else if (repetitions == 1) {
        intervalDays = 6;
      } else {
        intervalDays = math.max(1, (intervalDays * ease).round());
      }
      repetitions += 1;
    }
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
