import 'package:flutter/foundation.dart';

import '../core/json_file_store.dart';
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

  /// Whether the "plug in, keep the screen on" briefing has been shown.
  bool briefingSeen = false;

  /// The night currently being recorded, written every minute by the
  /// recording screen. If the app dies (battery, OS kill) it is promoted to a
  /// real session on the next launch, flagged as ended early, instead of the
  /// whole night vanishing.
  SleepSession? inProgress;

  /// True once at startup when [load] just rescued an [inProgress] night —
  /// the home screen tells the user rather than silently listing it.
  bool recoveredOnLaunch = false;

  final JsonFileStore _file = JsonFileStore('autosnore.json');

  /// The minute-by-minute checkpoint lives in its own small file: rewriting
  /// the whole history (Pro users keep every night) sixty times an hour
  /// would be gigabytes of I/O and a JSON encode on the UI isolate each time.
  final JsonFileStore _checkpoint = JsonFileStore('autosnore-inprogress.json');
  bool _proPending = false;

  Future<void> load() async {
    try {
      final raw = await _file.read();
      if (raw != null) {
        pro = raw['pro'] as bool? ?? false;
        sensitivity = (raw['sensitivity'] as num?)?.toDouble() ?? 0.5;
        briefingSeen = raw['briefingSeen'] as bool? ?? false;
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
      // A night that was being recorded when the app died: promote its last
      // checkpoint to a real session, flagged as ended early.
      final ip = await _checkpoint.read();
      final session = ip?['session'];
      if (session is Map<String, dynamic>) {
        try {
          final s = SleepSession.fromJson(session);
          if (s.durationMs > 60000 && !sessions.any((x) => x.id == s.id)) {
            sessions.add(s);
            recoveredOnLaunch = true;
            _sortAndPrune();
          }
        } catch (err) {
          debugPrint('autosnore could not recover in-progress night: $err');
        }
      }
    } catch (e) {
      debugPrint('autosnore load skipped: $e');
    } finally {
      loaded = true;
      final applyPro = _proPending;
      _proPending = false;
      if (applyPro) pro = true;
      if (recoveredOnLaunch) _checkpoint.write({});
      // Persist the recovery / late Pro right away.
      if (recoveredOnLaunch || applyPro) {
        _save();
      } else {
        notifyListeners();
      }
    }
  }

  void _save() {
    notifyListeners();
    if (!loaded) return;
    _file.write({
      'pro': pro,
      'sensitivity': sensitivity,
      'briefingSeen': briefingSeen,
      'sessions': sessions.map((s) => s.toJson()).toList(),
    });
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
    clearInProgress();
    sessions.removeWhere((x) => x.id == s.id);
    sessions.add(s);
    _sortAndPrune();
    _save();
  }

  /// Checkpoint the night being recorded (see [inProgress]). Only the
  /// checkpoint file is touched, never the main history.
  void saveInProgress(SleepSession s) {
    inProgress = s;
    _checkpoint.write({'session': s.toJson()});
  }

  void clearInProgress() {
    if (inProgress == null) return;
    inProgress = null;
    _checkpoint.write({});
  }

  void acknowledgeRecovery() {
    recoveredOnLaunch = false;
    notifyListeners();
  }

  void markBriefingSeen() {
    briefingSeen = true;
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
    if (!loaded) {
      _proPending = true;
      return;
    }
    pro = true;
    _save();
  }
}
