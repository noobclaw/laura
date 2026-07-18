import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'widget_bridge.dart';

/// In-memory model of all countdown events, backed by a single JSON file in the
/// app's documents directory. Everything stays on device — no network.
class EventStore extends ChangeNotifier {
  EventStore();

  /// Free tier tracks this many events; unlocking Pro removes the cap.
  static const int freeLimit = 5;

  final List<CountdownEvent> events = [];
  bool pro = false;
  bool loaded = false;

  int _idSeq = 0;

  String _newId() {
    _idSeq += 1;
    return 'evt-${DateTime.now().microsecondsSinceEpoch}-$_idSeq';
  }

  bool get atLimit => !pro && events.length >= freeLimit;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/daycount.json');
  }

  /// Load state from disk. Any failure (first launch, plugin missing in a test
  /// harness) leaves an empty store — the app still runs.
  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        pro = raw['pro'] as bool? ?? false;
        events
          ..clear()
          ..addAll((raw['events'] as List<dynamic>? ?? [])
              .map((e) => CountdownEvent.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('daycount load skipped: $e');
    } finally {
      loaded = true;
      notifyListeners();
      WidgetBridge.push(events);
    }
  }

  Future<void> _save() async {
    notifyListeners();
    WidgetBridge.push(events);
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({
          'pro': pro,
          'events': events.map((e) => e.toJson()).toList(),
        }),
        flush: true,
      );
    } catch (e) {
      debugPrint('daycount save skipped: $e');
    }
  }

  CountdownEvent add({
    required String title,
    required DateTime date,
    String emoji = '📅',
    int colorValue = 0xFFE7625F,
    bool pinned = false,
    bool yearlyRepeat = false,
    String note = '',
  }) {
    final e = CountdownEvent(
      id: _newId(),
      title: title.trim(),
      date: dateOnly(date),
      emoji: emoji,
      colorValue: colorValue,
      pinned: pinned,
      yearlyRepeat: yearlyRepeat,
      note: note.trim(),
    );
    events.add(e);
    _save();
    return e;
  }

  void update(CountdownEvent e) {
    e.title = e.title.trim();
    e.date = dateOnly(e.date);
    e.note = e.note.trim();
    _save();
  }

  void togglePin(CountdownEvent e) {
    e.pinned = !e.pinned;
    _save();
  }

  void delete(CountdownEvent e) {
    events.remove(e);
    _save();
  }

  void unlockPro() {
    pro = true;
    _save();
  }
}
