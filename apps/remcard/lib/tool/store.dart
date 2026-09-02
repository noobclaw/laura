import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'import_deck.dart';
import 'models.dart';

/// In-memory model of all decks, backed by a single JSON file in the app's
/// documents directory. Everything stays on device — no network, no accounts.
class RemcardStore extends ChangeNotifier {
  RemcardStore();

  /// Free tier allows this many decks; unlocking Pro removes the cap.
  static const int freeDeckLimit = 2;

  final List<Deck> decks = [];
  bool pro = false;
  bool loaded = false;

  int _idSeq = 0;

  String _newId(String prefix) {
    _idSeq += 1;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_idSeq';
  }

  bool get atDeckLimit => !pro && decks.length >= freeDeckLimit;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/remcard.json');
  }

  /// Set when the store's purchase stream reports Pro before [load] finished
  /// (StoreKit replays unfinished transactions at every launch). Applied after
  /// load so the unlock never triggers a save that would overwrite a file we
  /// have not read yet.
  bool _proPending = false;

  /// Saves run strictly one after another. Two overlapping writes to the same
  /// file could otherwise interleave, and the rename below assumes the temp
  /// file it just wrote is its own.
  Future<void> _saveChain = Future.value();

  /// Load state from disk. Any failure (e.g. first launch, or the plugin being
  /// unavailable in a test harness) leaves an empty in-memory store — the app
  /// still runs, just with no saved data.
  ///
  /// A file that exists but will not parse is renamed aside, not deleted: the
  /// user's decks are still in it, and the next save must not bury them under
  /// an empty store.
  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final text = await f.readAsString();
        try {
          final raw = jsonDecode(text) as Map<String, dynamic>;
          pro = raw['pro'] as bool? ?? false;
          decks
            ..clear()
            ..addAll((raw['decks'] as List<dynamic>? ?? [])
                .map((e) => Deck.fromJson(e as Map<String, dynamic>)));
        } catch (e) {
          debugPrint('remcard data unreadable, kept aside: $e');
          final aside =
              '${f.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
          try {
            await f.rename(aside);
          } catch (_) {
            // Could not move it; leave it and keep going with an empty store.
          }
        }
      }
    } catch (e) {
      debugPrint('remcard load skipped: $e');
    } finally {
      loaded = true;
      if (_proPending) {
        _proPending = false;
        pro = true;
        _save();
      } else {
        notifyListeners();
      }
    }
  }

  /// Persist the current state. The JSON is snapshotted synchronously so a
  /// mutation that lands while the previous write is in flight still ends up
  /// on disk in order. Never writes before [load] has run: an early save
  /// would replace real data with an empty store.
  void _save() {
    notifyListeners();
    if (!loaded) return;
    final payload = jsonEncode({
      'pro': pro,
      'decks': decks.map((d) => d.toJson()).toList(),
    });
    _saveChain = _saveChain.then((_) => _writeAtomically(payload));
  }

  /// Write to a sibling temp file, flush, then rename over the real one. A
  /// crash mid-write leaves either the old file or the new one — never half
  /// a JSON document that [load] would then discard.
  Future<void> _writeAtomically(String payload) async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('remcard save skipped: $e');
    }
  }

  Deck addDeck(String name) {
    final deck = Deck(id: _newId('deck'), name: name.trim());
    decks.add(deck);
    _save();
    return deck;
  }

  /// Create a deck pre-filled from an import. Every card is due immediately,
  /// like a hand-typed one — the schedule starts on first review, not from
  /// whatever the source file thought.
  Deck importDeck(String name, List<ImportedCard> cards) {
    final today = epochDayOf(DateTime.now());
    final deck = Deck(id: _newId('deck'), name: name.trim());
    for (final c in cards) {
      deck.cards.add(Flashcard(
        id: _newId('card'),
        front: c.front,
        back: c.back,
        dueDay: today,
      ));
    }
    decks.add(deck);
    _save();
    return deck;
  }

  void renameDeck(Deck deck, String name) {
    deck.name = name.trim();
    _save();
  }

  void deleteDeck(Deck deck) {
    decks.remove(deck);
    _save();
  }

  Flashcard addCard(Deck deck, String front, String back) {
    final today = epochDayOf(DateTime.now());
    final card = Flashcard(
      id: _newId('card'),
      front: front.trim(),
      back: back.trim(),
      dueDay: today, // new cards are due immediately
    );
    deck.cards.add(card);
    _save();
    return card;
  }

  void updateCard(Flashcard card, String front, String back) {
    card.front = front.trim();
    card.back = back.trim();
    _save();
  }

  void deleteCard(Deck deck, Flashcard card) {
    deck.cards.remove(card);
    _save();
  }

  /// Record one review and persist the new schedule.
  void reviewCard(Flashcard card, Rating rating) {
    card.review(rating, epochDayOf(DateTime.now()));
    _save();
  }

  /// Record the grade of a card shown again after lapsing in this session
  /// (see [Flashcard.relearn]).
  void relearnCard(Flashcard card, Rating rating) {
    card.relearn(rating, epochDayOf(DateTime.now()));
    _save();
  }

  void unlockPro() {
    if (!loaded) {
      _proPending = true;
      return;
    }
    pro = true;
    _save();
  }
}
