import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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

  /// Load state from disk. Any failure (e.g. first launch, or the plugin being
  /// unavailable in a test harness) leaves an empty in-memory store — the app
  /// still runs, just with no saved data.
  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        pro = raw['pro'] as bool? ?? false;
        decks
          ..clear()
          ..addAll((raw['decks'] as List<dynamic>? ?? [])
              .map((e) => Deck.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('remcard load skipped: $e');
    } finally {
      loaded = true;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({
          'pro': pro,
          'decks': decks.map((d) => d.toJson()).toList(),
        }),
        flush: true,
      );
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

  void unlockPro() {
    pro = true;
    _save();
  }
}
