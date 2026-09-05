import 'dart:math' as math;

import '../core/l10n.dart';
import 'fsrs.dart';

/// The four review grades shown to the user — FSRS's Again / Hard / Good /
/// Easy. Display labels live in the UI layer (study_screen.dart) so they
/// localize.
enum Rating { again, hard, good, easy }

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
/// Scheduling is FSRS (see `fsrs.dart`): [stability], [difficulty],
/// [repetitions], [lapses] and [lastReviewDay] are the scheduler's memory,
/// [dueDay] is where it put the card. The SM-2 fields ([ease],
/// [intervalDays]) are kept in step with the FSRS state and written to JSON
/// so a data file produced by this version still schedules sensibly in an
/// app version that only knows SM-2 (and vice versa: a file without FSRS
/// keys is converted on load, see [Flashcard.fromJson]).
///
/// A freshly created card is due immediately and has no memory state
/// ([isNew]).
class Flashcard {
  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    required this.dueDay,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
    this.stability = 0,
    this.difficulty = 0,
    this.lapses = 0,
    this.lastReviewDay,
  });

  final String id;
  String front;
  String back;

  /// SM-2 ease factor, derived from [difficulty] after every review. Only
  /// read back when a file has no FSRS keys.
  double ease;

  /// Interval the last review assigned, in days (`dueDay - lastReviewDay`).
  int intervalDays;

  /// Number of reviews recorded, including same-day relearn grades. Unlike
  /// SM-2's streak it never resets: a lapsed card is not a new card.
  int repetitions;

  /// FSRS stability in days; `0` until the first review.
  double stability;

  /// FSRS difficulty 1..10; `0` until the first review.
  double difficulty;

  /// Times the card was forgotten on a scheduled review.
  int lapses;

  /// Epoch day of the most recent review, or null if never reviewed.
  int? lastReviewDay;

  /// Epoch day on which this card next becomes due for review.
  int dueDay;

  /// Never reviewed: due now, no memory state yet.
  bool get isNew => repetitions == 0 || stability <= 0;

  bool isDue(int today) => dueDay <= today;

  /// Days until this card is next due, relative to [today] (0 = due now).
  int daysUntilDue(int today) => math.max(0, dueDay - today);

  FsrsMemory? get memory => isNew
      ? null
      : FsrsMemory(
          stability: stability,
          difficulty: difficulty,
          reps: repetitions,
          lapses: lapses,
        );

  /// Days since the last review as seen by the scheduler on [today]. Zero
  /// for a card never reviewed or reviewed earlier today.
  int _elapsed(int today) {
    final last = lastReviewDay;
    if (last == null) return 0;
    return math.max(0, today - last);
  }

  /// Fuzz seed: fixed for one card, one memory state and one day, so the
  /// interval shown on the grade button is the interval the tap assigns.
  int _fuzzSeed(int today) => Object.hash(id, repetitions, lastReviewDay, today);

  /// The interval [review] would assign for [rating] on [today], without
  /// mutating — shown on the grade buttons so the user sees the consequence
  /// of each choice before tapping, the way Anki does.
  int previewInterval(Rating rating, int today, Fsrs fsrs) {
    final next = fsrs.next(memory, rating, _elapsed(today));
    return fsrs.intervalFor(next.stability, fuzzSeed: _fuzzSeed(today));
  }

  /// Interval for grading a card that already lapsed *in this session* and
  /// is being shown again: a same-day review, which FSRS treats as a
  /// learning step (short-term stability) rather than a fresh recall on
  /// the forgetting curve. The lapse was already counted by [review].
  int previewRelearnInterval(Rating rating, int today, Fsrs fsrs) {
    final next = fsrs.next(memory, rating, 0);
    return fsrs.intervalFor(next.stability, fuzzSeed: _fuzzSeed(today));
  }

  /// See [previewRelearnInterval]: apply the relearn grade.
  void relearn(Rating rating, int today, Fsrs fsrs) =>
      _apply(fsrs.next(memory, rating, 0), today, fsrs);

  /// Apply one review with [rating] on the day [today].
  ///
  /// - Again: stability collapses to the post-lapse value; the study screen
  ///   re-shows the card in the same session, and the relearn grade then
  ///   decides when it comes back (usually within a few days).
  /// - Hard / Good / Easy: stability grows, more the closer the card was to
  ///   being forgotten and the easier the grade; difficulty drifts down on
  ///   Easy and up on Hard.
  void review(Rating rating, int today, Fsrs fsrs) =>
      _apply(fsrs.next(memory, rating, _elapsed(today)), today, fsrs);

  void _apply(FsrsMemory next, int today, Fsrs fsrs) {
    intervalDays =
        fsrs.intervalFor(next.stability, fuzzSeed: _fuzzSeed(today));
    stability = next.stability;
    difficulty = next.difficulty;
    repetitions = next.reps;
    lapses = next.lapses;
    ease = fsrs.easeFromDifficulty(next.difficulty);
    lastReviewDay = today;
    dueDay = today + intervalDays;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'front': front,
        'back': back,
        // Legacy SM-2 keys, kept so an older app version can still read the
        // file. Do not remove before every shipped version knows FSRS.
        'ease': ease,
        'intervalDays': intervalDays,
        'repetitions': repetitions,
        'dueDay': dueDay,
        // FSRS keys (schema 1).
        'fsrs': 1,
        'stability': stability,
        'difficulty': difficulty,
        'lapses': lapses,
        if (lastReviewDay != null) 'lastReviewDay': lastReviewDay,
      };

  /// Reads either schema. A card with SM-2 fields only (written by 1.1.x)
  /// is converted without changing when it is due:
  ///
  /// * stability = interval — at 90% retention FSRS's interval *is* the
  ///   stability, so the old schedule is carried over exactly;
  /// * difficulty from ease (see [Fsrs.difficultyFromEase]);
  /// * last review = due day − interval, so the elapsed time the next
  ///   review sees is the interval the old scheduler intended;
  /// * a card with no interval yet stays new.
  factory Flashcard.fromJson(Map<String, dynamic> j) {
    final ease = (j['ease'] as num?)?.toDouble() ?? 2.5;
    final interval = (j['intervalDays'] as num?)?.toInt() ?? 0;
    final reps = (j['repetitions'] as num?)?.toInt() ?? 0;
    final due = (j['dueDay'] as num?)?.toInt() ?? 0;
    final card = Flashcard(
      // A missing id must not throw: that would make load() judge the whole
      // file corrupt and hide every deck.
      id: j['id'] as String? ?? _fallbackId('card'),
      front: j['front'] as String? ?? '',
      back: j['back'] as String? ?? '',
      ease: ease,
      intervalDays: interval,
      repetitions: reps,
      dueDay: due,
    );
    final stability = (j['stability'] as num?)?.toDouble();
    if (stability != null && stability > 0) {
      card.stability = stability;
      card.difficulty =
          ((j['difficulty'] as num?)?.toDouble() ?? 0).clamp(1.0, 10.0);
      card.lapses = (j['lapses'] as num?)?.toInt() ?? 0;
      card.lastReviewDay = (j['lastReviewDay'] as num?)?.toInt();
      if (card.repetitions == 0) card.repetitions = 1;
    } else if (interval > 0) {
      // SM-2 → FSRS. A lapsed-and-relearned card has repetitions 0 but an
      // interval; it has been reviewed, so it is not new.
      card.stability = interval.toDouble();
      card.difficulty = const Fsrs().difficultyFromEase(ease);
      card.lastReviewDay = due - interval;
      if (card.repetitions == 0) card.repetitions = 1;
    }
    return card;
  }
}

int _fallbackSeq = 0;

/// Id for a stored record that lost its own (hand-edited or truncated file).
String _fallbackId(String prefix) =>
    '$prefix-recovered-${DateTime.now().microsecondsSinceEpoch}-${_fallbackSeq++}';

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
        id: j['id'] as String? ?? _fallbackId('deck'),
        name: j['name'] as String? ?? '',
        cards: (j['cards'] as List<dynamic>? ?? [])
            .map((e) => Flashcard.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
