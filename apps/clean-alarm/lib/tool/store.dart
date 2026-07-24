import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'scheduler.dart';

/// In-memory model of all alarms, backed by a single JSON file in the app's
/// documents directory. Everything stays on device — no network. Every mutation
/// re-syncs the platform alarm schedule.
class AlarmStore extends ChangeNotifier {
  AlarmStore({this.scheduler});

  /// Injectable for tests; production passes the real scheduler.
  final AlarmScheduler? scheduler;

  /// Free tier allows this many alarms; Pro removes the cap.
  static const int freeLimit = 5;

  final List<AlarmItem> alarms = [];
  bool pro = false;
  bool loaded = false;

  /// Index into [accentPalette]; Pro unlocks non-default colors.
  int accent = 0;
  int _notifSeq = 1;

  bool get atLimit => !pro && alarms.length >= freeLimit;

  int _nextNotifId() => _notifSeq++;

  String _newId() => 'alm-${DateTime.now().microsecondsSinceEpoch}-$_notifSeq';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/clean_alarm.json');
  }

  /// Load state from disk. Any failure (first launch, plugin missing in a test
  /// harness) leaves an empty store — the app still runs.
  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        pro = raw['pro'] as bool? ?? false;
        accent = (raw['accent'] as num?)?.toInt() ?? 0;
        _notifSeq = (raw['notifSeq'] as num?)?.toInt() ?? 1;
        alarms
          ..clear()
          ..addAll((raw['alarms'] as List<dynamic>? ?? [])
              .map((e) => AlarmItem.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('clean_alarm load skipped: $e');
    } finally {
      loaded = true;
      notifyListeners();
      await _resync();
    }
  }

  Future<void> _resync() async {
    try {
      await scheduler?.syncAll(alarms);
    } catch (e) {
      debugPrint('clean_alarm resync skipped: $e');
    }
  }

  Future<void> _save() async {
    notifyListeners();
    await _resync();
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({
          'pro': pro,
          'accent': accent,
          'notifSeq': _notifSeq,
          'alarms': alarms.map((a) => a.toJson()).toList(),
        }),
        flush: true,
      );
    } catch (e) {
      debugPrint('clean_alarm save skipped: $e');
    }
  }

  AlarmItem add({
    required int hour,
    required int minute,
    String label = '',
    Set<int>? weekdays,
    bool soundOn = true,
    bool vibrate = true,
    int snoozeMinutes = 5,
  }) {
    final a = AlarmItem(
      id: _newId(),
      notifId: _nextNotifId(),
      hour: hour,
      minute: minute,
      label: label.trim(),
      weekdays: weekdays,
      soundOn: soundOn,
      vibrate: vibrate,
      snoozeMinutes: snoozeMinutes,
    );
    alarms.add(a);
    _sort();
    _save();
    return a;
  }

  void update(AlarmItem a) {
    a.label = a.label.trim();
    _sort();
    _save();
  }

  void toggle(AlarmItem a, bool enabled) {
    a.enabled = enabled;
    _save();
  }

  void delete(AlarmItem a) {
    alarms.remove(a);
    _save();
  }

  void unlockPro() {
    pro = true;
    _save();
  }

  void setAccent(int i) {
    accent = i;
    _save();
  }

  /// Sort by ring time-of-day so the list reads top-to-bottom like a schedule.
  void _sort() {
    alarms.sort((a, b) {
      final ta = a.hour * 60 + a.minute;
      final tb = b.hour * 60 + b.minute;
      return ta.compareTo(tb);
    });
  }
}

/// Accent colors offered in settings. Index 0 is the free default (the brand
/// teal); the rest are a Pro perk.
const List<int> accentPalette = [
  0xFF00897B, // teal (default / free)
  0xFF5C6BC0, // indigo
  0xFFEF6C00, // amber
  0xFFE53935, // red
  0xFF43A047, // green
  0xFF8E24AA, // purple
];
