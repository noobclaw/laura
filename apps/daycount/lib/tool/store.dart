import 'package:flutter/foundation.dart';

import '../core/json_file_store.dart';
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

  final JsonFileStore _file = JsonFileStore('daycount.json');

  /// Pro reported by the store before [load] finished (StoreKit replays
  /// transactions at launch); applied after load so it never triggers a
  /// save over a file we have not read yet.
  bool _proPending = false;

  int _idSeq = 0;

  String _newId() {
    _idSeq += 1;
    return 'evt-${DateTime.now().microsecondsSinceEpoch}-$_idSeq';
  }

  bool get atLimit => !pro && events.length >= freeLimit;

  /// Load state from disk. Any failure (first launch, plugin missing in a test
  /// harness, damaged file — which is kept aside) leaves an empty store; the
  /// app still runs.
  Future<void> load() async {
    try {
      final raw = await _file.read();
      if (raw != null) {
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
      if (_proPending) {
        _proPending = false;
        pro = true;
        _save();
      } else {
        notifyListeners();
      }
      WidgetBridge.push(events);
    }
  }

  /// Persist atomically (see [JsonFileStore]) and refresh the widget. Never
  /// writes before [load] has run.
  void _save() {
    notifyListeners();
    WidgetBridge.push(events);
    if (!loaded) return;
    _file.write({
      'pro': pro,
      'events': events.map((e) => e.toJson()).toList(),
    });
  }

  /// All events, exported as one JSON document (share / backup).
  Map<String, dynamic> exportJson() => {
        'app': 'daycount',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'events': events.map((e) => e.toJson()).toList(),
      };

  /// Merge events from an [exportJson] document. Returns how many were added;
  /// entries whose id already exists are skipped so re-importing a backup
  /// does not duplicate.
  int importJson(Map<String, dynamic> doc) {
    final existing = events.map((e) => e.id).toSet();
    var added = 0;
    for (final raw in (doc['events'] as List<dynamic>? ?? [])) {
      try {
        final e = CountdownEvent.fromJson(raw as Map<String, dynamic>);
        if (existing.contains(e.id)) continue;
        if (atLimit) break;
        events.add(e);
        existing.add(e.id);
        added++;
      } catch (err) {
        debugPrint('daycount import skipped one entry: $err');
      }
    }
    if (added > 0) _save();
    return added;
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

  /// Re-broadcast state without changing it — for the day-change notifier,
  /// so every "N days" on screen is recomputed against the new date.
  void touch() => notifyListeners();

  void unlockPro() {
    if (!loaded) {
      _proPending = true;
      return;
    }
    pro = true;
    _save();
  }
}
