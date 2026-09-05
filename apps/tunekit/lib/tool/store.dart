import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/json_file_store.dart';
import 'music/metronome_math.dart';

/// One calendar day of practice. Seconds per tool, tuning accuracy samples,
/// drill answers. Everything the log page draws comes from these.
class DayLog {
  DayLog();

  int tunerSec = 0;
  int metroSec = 0;
  int practiceSec = 0;

  /// Stable tuner readings and how far off they were, in cents.
  int tuneSamples = 0;
  double tuneAbsCentsSum = 0;
  int inTuneSamples = 0;

  int drillAnswered = 0;
  int drillCorrect = 0;
  int checksPassed = 0;

  int get totalSec => tunerSec + metroSec + practiceSec;
  int get totalMinutes => totalSec ~/ 60;

  /// Mean |cents| of the day's stable readings, or null.
  double? get meanAbsCents => tuneSamples == 0 ? null : tuneAbsCentsSum / tuneSamples;

  /// Share of stable readings inside ±5 cents, 0..1, or null.
  double? get inTuneRatio => tuneSamples == 0 ? null : inTuneSamples / tuneSamples;

  Map<String, dynamic> toJson() => {
        'tuner': tunerSec,
        'metro': metroSec,
        'practice': practiceSec,
        'ts': tuneSamples,
        'tc': tuneAbsCentsSum,
        'ti': inTuneSamples,
        'da': drillAnswered,
        'dc': drillCorrect,
        'cp': checksPassed,
      };

  static int _i(dynamic v) => v is num ? v.toInt() : 0;
  static double _d(dynamic v) => v is num ? v.toDouble() : 0;

  static DayLog fromJson(Map<String, dynamic> j) => DayLog()
    ..tunerSec = _i(j['tuner'])
    ..metroSec = _i(j['metro'])
    ..practiceSec = _i(j['practice'])
    ..tuneSamples = _i(j['ts'])
    ..tuneAbsCentsSum = _d(j['tc'])
    ..inTuneSamples = _i(j['ti'])
    ..drillAnswered = _i(j['da'])
    ..drillCorrect = _i(j['dc'])
    ..checksPassed = _i(j['cp']);
}

enum PracticeTool { tuner, metro, practice }

/// Everything the app remembers, in one JSON document in the app sandbox:
/// the Pro flag, tuner/metronome preferences and the practice log.
class TuneKitStore extends ChangeNotifier {
  TuneKitStore({JsonFileStore? file}) : _file = file ?? JsonFileStore('tunekit.json');

  /// Free tier sees this many days of history.
  static const int freeHistoryDays = 7;

  final JsonFileStore _file;
  bool loaded = false;
  bool pro = false;

  double a4 = 440;
  String instrumentId = 'chromatic';
  String practiceInstrumentId = 'guitar';
  int bpm = 100;
  int timeSignatureIndex = 2; // 4/4
  int subdivisionIndex = 0; // quarter
  int drillBest = 0;

  final Map<String, DayLog> days = {};

  Timer? _flushTimer;
  bool _dirty = false;

  static String keyFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DayLog today() => days.putIfAbsent(keyFor(DateTime.now()), DayLog.new);

  DayLog? dayAt(DateTime d) => days[keyFor(d)];

  TimeSignature get timeSignature =>
      kTimeSignatures[timeSignatureIndex.clamp(0, kTimeSignatures.length - 1)];
  Subdivision get subdivision =>
      Subdivision.values[subdivisionIndex.clamp(0, Subdivision.values.length - 1)];

  Future<void> load() async {
    // StoreKit replays transactions at launch, so an unlock can arrive
    // before the file is read (or before any file exists); it must survive
    // the read and reach the disk.
    Map<String, dynamic>? raw;
    try {
      raw = await _file.read();
      if (raw != null) _apply(raw);
    } catch (e) {
      debugPrint('tunekit load failed: $e');
    } finally {
      loaded = true;
      if (pro && raw?['pro'] != true) _save();
      notifyListeners();
    }
  }

  void _apply(Map<String, dynamic> raw) {
    // Every field is read defensively: a type that changes in a later
    // version must cost that preference, never the whole log.
    pro = pro || raw['pro'] == true;
    if (raw['a4'] is num) a4 = (raw['a4'] as num).toDouble().clamp(430, 450);
    if (raw['instrument'] is String) instrumentId = raw['instrument'] as String;
    if (raw['practiceInstrument'] is String) practiceInstrumentId = raw['practiceInstrument'] as String;
    if (raw['bpm'] is num) bpm = clampBpm((raw['bpm'] as num).toInt());
    if (raw['sig'] is num) timeSignatureIndex = (raw['sig'] as num).toInt().clamp(0, kTimeSignatures.length - 1);
    if (raw['sub'] is num) subdivisionIndex = (raw['sub'] as num).toInt().clamp(0, Subdivision.values.length - 1);
    if (raw['drillBest'] is num) drillBest = (raw['drillBest'] as num).toInt();
    final d = raw['days'];
    if (d is Map) {
      d.forEach((k, v) {
        if (k is String && v is Map<String, dynamic>) days[k] = DayLog.fromJson(v);
      });
    }
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'pro': pro,
        'a4': a4,
        'instrument': instrumentId,
        'practiceInstrument': practiceInstrumentId,
        'bpm': bpm,
        'sig': timeSignatureIndex,
        'sub': subdivisionIndex,
        'drillBest': drillBest,
        'days': {for (final e in days.entries) e.key: e.value.toJson()},
      };

  void _save() {
    if (!loaded) return; // never clobber the file with defaults before reading it
    _dirty = false;
    _file.write(toJson());
  }

  /// Seconds tick every second while a tool is in use; batch those writes.
  void _saveSoon() {
    _dirty = true;
    _flushTimer ??= Timer(const Duration(seconds: 15), () {
      _flushTimer = null;
      if (_dirty) _save();
    });
  }

  /// Write pending changes now (app going to background).
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_dirty) _save();
    await _file.flush();
  }

  void unlockPro() {
    if (pro) return;
    pro = true;
    _save();
    notifyListeners();
  }

  void setA4(double v) {
    a4 = v.clamp(430, 450);
    _save();
    notifyListeners();
  }

  void setInstrument(String id) {
    instrumentId = id;
    _save();
    notifyListeners();
  }

  void setPracticeInstrument(String id) {
    practiceInstrumentId = id;
    _save();
    notifyListeners();
  }

  void setMetronome({int? bpm, int? sigIndex, int? subIndex}) {
    if (bpm != null) this.bpm = clampBpm(bpm);
    if (sigIndex != null) timeSignatureIndex = sigIndex;
    if (subIndex != null) subdivisionIndex = subIndex;
    _saveSoon();
    notifyListeners();
  }

  void addSeconds(PracticeTool tool, int sec) {
    final d = today();
    switch (tool) {
      case PracticeTool.tuner:
        d.tunerSec += sec;
      case PracticeTool.metro:
        d.metroSec += sec;
      case PracticeTool.practice:
        d.practiceSec += sec;
    }
    _saveSoon();
    notifyListeners();
  }

  void addTuneSample(double absCents, {required bool inTune}) {
    final d = today();
    d.tuneSamples++;
    d.tuneAbsCentsSum += absCents;
    if (inTune) d.inTuneSamples++;
    _saveSoon();
  }

  void addDrillAnswer({required bool correct, required int score}) {
    final d = today();
    d.drillAnswered++;
    if (correct) d.drillCorrect++;
    if (score > drillBest) drillBest = score;
    _saveSoon();
    notifyListeners();
  }

  void addCheckPassed() {
    today().checksPassed++;
    _saveSoon();
    notifyListeners();
  }

  /// Consecutive days ending today (or yesterday, if today is still empty)
  /// with at least one minute of practice.
  int get streak {
    var day = DateTime.now();
    var count = 0;
    final todayLog = dayAt(day);
    // Calendar arithmetic, not 24-hour subtraction: across a DST change a
    // Duration-based step lands on the wrong date.
    if (todayLog == null || todayLog.totalSec < 60) {
      day = DateTime(day.year, day.month, day.day - 1);
    }
    while (true) {
      final log = dayAt(day);
      if (log == null || log.totalSec < 60) break;
      count++;
      day = DateTime(day.year, day.month, day.day - 1);
      if (count > 3650) break;
    }
    return count;
  }

  /// Days the current tier may display, newest last.
  List<DateTime> visibleDays(int wanted) {
    final n = pro ? wanted : wanted.clamp(0, freeHistoryDays);
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    return [for (var i = n - 1; i >= 0; i--) DateTime(base.year, base.month, base.day - i)];
  }

  /// Sum of a field over the last [n] days (tier-limited).
  int totalSeconds(int n) =>
      visibleDays(n).fold(0, (acc, d) => acc + (dayAt(d)?.totalSec ?? 0));

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }
}
