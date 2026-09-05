import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/json_file_store.dart';
import 'eta.dart';
import 'models.dart';
import 'quota.dart';

/// In-memory model of settings, the free-tier quota and the history of
/// processed photos, backed by one JSON file plus a `lifted/` folder of
/// source copies and results in the app documents directory. Nothing ever
/// leaves the device unless the user taps Save / Share.
class PhotoLiftStore extends ChangeNotifier {
  PhotoLiftStore();

  /// Free tier: this many photos per day at 2x, with the corner tag.
  static const int freeDailyLimit = 3;

  bool pro = false;
  /// What the file said at load time; false until load() has read it.
  bool proOnDisk = false;
  bool useGpu = true;
  DenoiseLevel defaultDenoise = DenoiseLevel.light;
  final List<LiftRecord> history = [];
  EtaModel eta = EtaModel();
  /// Engine that produced the last result — seeds the estimate shown before
  /// the next run. Conservative default until something has run.
  EngineKind lastEngine = EngineKind.ncnnCpu;
  bool loaded = false;

  Directory? _dir;
  int _idSeq = 0;

  final JsonFileStore _state = JsonFileStore('photolift.json');

  String newId() {
    _idSeq += 1;
    return '${DateTime.now().millisecondsSinceEpoch}-$_idSeq';
  }

  /// Absolute path of a file in the private `lifted/` folder.
  String pathFor(String fileName) => '${_dir?.path ?? ''}/$fileName';

  String sourcePath(LiftRecord r) => pathFor(r.sourceName);
  String outputPath(LiftRecord r) => pathFor(r.outputName);

  /// Load state from disk. Any failure (first launch, or plugins unavailable
  /// in a test harness) leaves an empty but usable store.
  Future<void> load() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      _dir = Directory('${docs.path}/lifted');
      if (!await _dir!.exists()) await _dir!.create(recursive: true);
      final raw = await _state.read();
      if (raw != null) {
        // StoreKit may replay a purchase before load() finishes; never let the
        // stale value on disk undo an unlock that already happened.
        proOnDisk = raw['pro'] as bool? ?? false;
        pro = pro || proOnDisk;
        useGpu = raw['useGpu'] as bool? ?? true;
        defaultDenoise = DenoiseLevel.fromIndex((raw['defaultDenoise'] as num?)?.toInt());
        _quotaState = DailyQuota.fromJson(
            raw['quota'] as Map<String, dynamic>?, limit: freeDailyLimit);
        lastEngine = EngineKind.fromWire(raw['lastEngine'] as String?);
        final rates = raw['eta'];
        if (rates is Map) {
          eta = EtaModel({
            for (final e in rates.entries)
              if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
          });
        }
        history
          ..clear()
          ..addAll((raw['history'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(LiftRecord.fromJson)
              .whereType<LiftRecord>());
        history.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    } catch (e) {
      debugPrint('photolift load skipped: $e');
    } finally {
      loaded = true;
      // An unlock that arrived before the file was read was only applied in
      // memory (writes are refused until load completes) - persist it now.
      if (pro && !proOnDisk) {
        _save();
      } else {
        notifyListeners();
      }
      _sweepOrphans();
    }
  }

  /// Deletes files in `lifted/` that no history entry references: leftovers
  /// of a job that died between writing and booking (crash, OOM kill).
  Future<void> _sweepOrphans() async {
    final d = _dir;
    if (d == null) return;
    final keep = <String>{
      for (final r in history) ...[r.sourceName, r.outputName],
    };
    try {
      await for (final e in d.list()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        final orphan = name.endsWith('.tmp') ||
            ((name.startsWith('src_') || name.startsWith('out_')) &&
                !keep.contains(name));
        if (orphan) {
          try {
            await e.delete();
          } catch (err) {
            debugPrint('orphan delete $name failed: $err');
          }
        }
      }
    } catch (e) {
      debugPrint('orphan sweep skipped: $e');
    }
  }

  DailyQuota _quotaState = DailyQuota(limit: freeDailyLimit);

  /// Photos still allowed today on the free tier (Pro: unlimited).
  int remainingToday([DateTime? now]) =>
      pro ? -1 : _quotaState.remaining(now ?? DateTime.now());

  int usedToday([DateTime? now]) => _quotaState.used(now ?? DateTime.now());

  /// Called by the day-change notifier so quota-bound widgets rebuild.
  void dayChanged() => notifyListeners();

  /// Whether a job with [scale] may start. 4x and the daily cap are Pro.
  bool canStart({required int scale, DateTime? now}) {
    if (pro) return true;
    if (scale != 2) return false;
    return _quotaState.canUse(now ?? DateTime.now());
  }

  /// Records a free-tier use; Pro never consumes quota.
  void consumeQuota([DateTime? now]) {
    if (pro) return;
    _quotaState.consume(now ?? DateTime.now());
    _save();
  }

  void unlockPro() {
    if (pro) return;
    pro = true;
    _save(); // no-op before load(); load()'s finally persists it then
  }

  void setUseGpu(bool v) {
    useGpu = v;
    _save();
  }

  void setDefaultDenoise(DenoiseLevel d) {
    defaultDenoise = d;
    _save();
  }

  void recordEta(LiftRecord r) {
    eta.record(r.outWidth * r.outHeight, r.engine, r.elapsedMs, scale: r.scale);
    lastEngine = r.engine;
    _save();
  }

  /// Estimated seconds for an output of [outPixels] at [scale] on the engine
  /// that ran last (or the conservative default before any run).
  double estimateSeconds(int outPixels, int scale) =>
      eta.estimateSeconds(outPixels, lastEngine, scale: scale);

  Future<void> clearHistory() async {
    final all = List.of(history);
    for (final r in all) {
      await deleteRecord(r);
    }
  }

  /// Copies the picked photo into `lifted/` so the before/after view keeps
  /// its "before" after the picker cache is purged. Returns the file name.
  Future<String> importSource(String pickedPath, String id) async {
    final ext = pickedPath.contains('.') ? pickedPath.split('.').last.toLowerCase() : 'jpg';
    final name = 'src_$id.$ext';
    await File(pickedPath).copy(pathFor(name));
    return name;
  }

  String outputNameFor(String id) => 'out_$id.jpg';

  void addRecord(LiftRecord r) {
    history.insert(0, r);
    _save();
  }

  Future<void> deleteRecord(LiftRecord r) async {
    history.removeWhere((x) => x.id == r.id);
    _save();
    for (final p in [sourcePath(r), outputPath(r)]) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('delete $p failed: $e');
      }
    }
  }

  /// Bytes used by the private library (for the settings row).
  Future<int> libraryBytes() async {
    final d = _dir;
    if (d == null || !await d.exists()) return 0;
    var total = 0;
    await for (final e in d.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  void _save() {
    notifyListeners();
    if (!loaded) return; // never overwrite a file we have not read yet
    _state.write({
      'pro': pro,
      'useGpu': useGpu,
      'defaultDenoise': defaultDenoise.index,
      'quota': _quotaState.toJson(),
      'eta': eta.toJson(),
      'lastEngine': lastEngine.wire,
      'history': history.map((r) => r.toJson()).toList(),
    });
  }
}
