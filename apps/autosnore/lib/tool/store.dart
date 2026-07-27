import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// All app state, backed by a single JSON file in the app sandbox. No network,
/// no account — recordings never leave the device (they are never even audio,
/// only loudness metadata). Mirrors the shell's other stores.
class AutoSnoreStore extends ChangeNotifier {
  AutoSnoreStore();

  /// Free tier keeps this many most-recent nights; Pro removes the cap.
  static const int freeSessionLimit = 3;

  final List<SleepSession> sessions = []; // newest first
  bool pro = false;
  bool loaded = false;

  /// Detector sensitivity 0..1 (0.5 default). Persisted so it survives restarts.
  double sensitivity = 0.5;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/autosnore.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        pro = raw['pro'] as bool? ?? false;
        sensitivity = (raw['sensitivity'] as num?)?.toDouble() ?? 0.5;
        sessions.clear();
        // Parse per-element so one corrupt record can't wipe the whole history.
        for (final e in (raw['sessions'] as List<dynamic>? ?? [])) {
          try {
            sessions.add(SleepSession.fromJson(e as Map<String, dynamic>));
          } catch (err) {
            debugPrint('autosnore skipped bad session: $err');
          }
        }
        _sortAndPrune();
      }
    } catch (e) {
      debugPrint('autosnore load skipped: $e');
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
          'sensitivity': sensitivity,
          'sessions': sessions.map((s) => s.toJson()).toList(),
        }),
        flush: true,
      );
    } catch (e) {
      debugPrint('autosnore save skipped: $e');
    }
  }

  void _sortAndPrune() {
    sessions.sort((a, b) => b.startMs.compareTo(a.startMs));
    if (!pro && sessions.length > freeSessionLimit) {
      sessions.removeRange(freeSessionLimit, sessions.length);
    }
  }

  /// True when the free history cap is full — the UI nudges toward Pro.
  bool get atFreeLimit => !pro && sessions.length >= freeSessionLimit;

  void addSession(SleepSession s) {
    sessions.add(s);
    _sortAndPrune();
    _save();
  }

  void deleteSession(String id) {
    sessions.removeWhere((s) => s.id == id);
    _save();
  }

  void setSensitivity(double v) {
    sensitivity = v.clamp(0.0, 1.0);
    _save();
  }

  void unlockPro() {
    pro = true;
    _save();
  }
}
