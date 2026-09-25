import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../bench/atomic_file.dart';

/// The only place in the app that calls [HapticFeedback] (F14). Call sites
/// name an event, never an intensity; one event fires once, on the frame the
/// state actually changed. `heavyImpact` is never used.
///
/// Map (brief §11):
/// - [run]     run / stop                    → medium
/// - [commit]  part placed, wire made, move dropped, saved, deleted → light
/// - [select]  probe, long-press, undo/redo, wire mode, switch flip → selection
abstract final class BenchHaptics {
  /// The in-app master switch (Settings). Persisted on device.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static final AtomicJsonFile _file = AtomicJsonFile('ohm_prefs.json');
  static bool _loaded = false;

  /// Read the saved switch. Call once before `runApp`; safe to call again.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _file.read();
      if (raw?['haptics'] == false) enabled.value = false;
    } catch (e) {
      debugPrint('prefs load skipped: $e');
    }
  }

  static void setEnabled(bool on) {
    enabled.value = on;
    _file.write({'haptics': on});
  }

  static void run() => _fire(HapticFeedback.mediumImpact);
  static void commit() => _fire(HapticFeedback.lightImpact);
  static void select() => _fire(HapticFeedback.selectionClick);

  static void _fire(Future<void> Function() slot) {
    if (!enabled.value) return;
    slot();
  }
}
