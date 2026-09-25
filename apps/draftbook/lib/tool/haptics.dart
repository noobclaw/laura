import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/json_file_store.dart';

/// Every vibration in the app goes through here (kb F14): three events, one
/// intensity each, one switch in Settings.
///
/// | event     | when                                            | verb            |
/// |-----------|-------------------------------------------------|-----------------|
/// | select    | a format button, a goal chip, a scene status    | selectionClick  |
/// | commit    | start / keep writing, restore a version, export | lightImpact     |
/// | milestone | the first time today's words cross the goal     | mediumImpact    |
///
/// Errors are deliberately silent, and heavyImpact is never used.
abstract final class Haptics {
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  /// Its own small document: a preference must never ride along with (or be
  /// lost with) the manuscript file.
  static final JsonFileStore _file = JsonFileStore('draftbook_prefs.json');
  static bool _loaded = false;

  /// The day (yyyy-mm-dd) the goal milestone last fired. Kept on disk with
  /// the switch: held only in memory, every cold start re-ran the gauge from
  /// zero past the goal and buzzed again (kb F14 一个事件只震一次).
  static String _milestoneDay = '';

  static Future<void> load() async {
    try {
      final doc = await _file.read();
      enabled.value = doc?['haptics'] as bool? ?? true;
      _milestoneDay = doc?['milestoneDay'] as String? ?? '';
    } catch (e) {
      // Unreadable preference: keep the default (on) and say why in the log.
      debugPrint('draftbook prefs not read: $e');
    }
    _loaded = true;
  }

  static void setEnabled(bool value) {
    enabled.value = value;
    _save();
  }

  static void _save() {
    if (_loaded) _file.write({'haptics': enabled.value, 'milestoneDay': _milestoneDay});
  }

  static void select() => _fire(HapticFeedback.selectionClick);
  static void commit() => _fire(HapticFeedback.lightImpact);
  static void milestone() => _fire(HapticFeedback.mediumImpact);

  /// The goal milestone for [day]: fires once for that day, ever — not once
  /// per launch. Returns whether it fired.
  static bool milestoneOnce(String day) {
    if (_milestoneDay == day) return false;
    _milestoneDay = day;
    _save();
    milestone();
    return true;
  }

  /// Tests and the screenshot harness start every run from a blank day
  /// (through `LineGauge.resetMemory`).
  static void resetMilestone() => _milestoneDay = '';

  static void _fire(Future<void> Function() verb) {
    if (!enabled.value) return;
    unawaited(verb().catchError((Object e) {
      // A device without a haptic engine; nothing to tell the writer.
      debugPrint('haptic skipped: $e');
    }));
  }
}
