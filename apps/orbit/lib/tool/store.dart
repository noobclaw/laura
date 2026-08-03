import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/l10n.dart';
import 'catalog.dart';
import 'models.dart';
import 'passes.dart';
import 'sgp4.dart';

/// Everything the app remembers, in one JSON file inside the app sandbox, plus
/// the pass search that drives every screen. Nothing is uploaded, nothing is
/// fetched — the only way new orbital data enters is the user pasting it.
class OrbitStore extends ChangeNotifier {
  OrbitStore();

  /// Free tier: the eight named headliners, two days ahead.
  static const int freeWindowDays = 2;
  static const int proMaxWindowDays = 10;

  /// Passes lower than this are usually behind a building and rarely worth a
  /// trip outside; Pro can drop the bar to see marginal and radio passes.
  static const double defaultMinElevation = 10.0;
  static const double proMinElevation = 5.0;

  /// Ceiling on how many passes one forecast returns. A ten-day full-catalogue
  /// search legitimately produces thousands; past a few hundred the list stops
  /// being a timetable and starts being a wall, and every extra entry has to
  /// cross an isolate boundary as JSON. The cap is applied *after* sorting, so
  /// what is dropped is the far end of the window — and the UI says so.
  static const int maxPasses = 500;

  /// Refuse absurd pastes rather than freezing the UI thread parsing them. The
  /// whole visible-satellite catalogue is about 24 KB; a megabyte is somebody
  /// pasting the entire active-satellite list, which this app cannot usefully
  /// search anyway.
  static const int maxImportBytes = 1024 * 1024;

  bool loaded = false;
  bool pro = false;
  ObserverSite? site;
  String importedTleText = '';

  int windowDays = freeWindowDays;

  /// Pro switch: include passes where the satellite is in the Earth's shadow or
  /// the sky is not fully dark. Useless to the naked eye, useful to anyone with
  /// a radio or a tracking mount.
  bool includeDarkPasses = false;

  List<SatEntry> catalog = const [];
  List<SatPass> passes = const [];

  bool searching = false;
  String? searchError;

  /// Set when the bundled catalogue could not be read at all — without this the
  /// app would just show "0 targets" everywhere and never say why.
  String? loadError;
  DateTime? lastSearchAt;

  /// True when the forecast hit [maxPasses] and the tail of the timeline was
  /// dropped. Surfaced in the UI — a capped list must never look complete.
  bool passesTruncated = false;

  int _searchToken = 0;
  int _catalogToken = 0;

  bool get hasSite => site != null;

  /// Satellites the current tier may track.
  List<SatEntry> get trackable =>
      pro ? catalog : SatelliteCatalog.freeTier(catalog);

  double get catalogAgeDays =>
      SatelliteCatalog.medianAgeDays(trackable, DateTime.now());

  ElementFreshness get freshness => freshnessOf(catalogAgeDays);

  int get maxWindowDays => pro ? proMaxWindowDays : freeWindowDays;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/orbit.json');
  }

  Future<void> load() async {
    try {
      final bundled = await SatelliteCatalog.loadBundled();
      // Every read of the settings file is best-effort: a truncated write, a
      // hand-edited file or a field that changes type in a future version must
      // cost the user their preferences at worst, never the catalogue.
      try {
        final f = await _file();
        final backup = File('${f.path}.bak');
        final source = await f.exists()
            ? f
            : (await backup.exists() ? backup : null);
        if (source != null) {
          final raw = jsonDecode(await source.readAsString());
          if (raw is Map<String, dynamic>) {
            pro = raw['pro'] is bool ? raw['pro'] as bool : false;
            site = ObserverSite.fromJson(
                raw['site'] is Map<String, dynamic>
                    ? raw['site'] as Map<String, dynamic>
                    : null);
            importedTleText = raw['tle'] is String ? raw['tle'] as String : '';
            includeDarkPasses = raw['dark'] is bool ? raw['dark'] as bool : false;
            windowDays =
                raw['window'] is num ? (raw['window'] as num).toInt() : freeWindowDays;
            windowDays = windowDays.clamp(1, maxWindowDays);
          }
        }
      } catch (e) {
        debugPrint('orbit: settings unreadable, starting fresh: $e');
      }

      final imported = importedTleText.trim().isEmpty
          ? const <SatEntry>[]
          : SatelliteCatalog.parse(importedTleText, imported: true);
      catalog = SatelliteCatalog.merge(bundled, imported);
      loadError = null;
    } catch (e) {
      debugPrint('orbit load failed: $e');
      catalog = const [];
      loadError = tr(
        zh: '内置轨道目录加载失败,预报暂时无法计算。重装应用通常可以修复。',
        en: 'The bundled orbital catalogue could not be loaded, so no forecast can be computed. Reinstalling usually fixes this.',
      );
    } finally {
      loaded = true;
      notifyListeners();
      if (hasSite && catalog.isNotEmpty) {
        unawaited(refresh());
      }
    }
  }

  /// Writes to a sibling temp file and renames over the real one. A plain
  /// truncate-then-write loses the observing site and every imported element
  /// set if the process dies mid-write, and the file is not small.
  Future<void> _save() async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'pro': pro,
          'site': site?.toJson(),
          'tle': importedTleText,
          'dark': includeDarkPasses,
          'window': windowDays,
        }),
        flush: true,
      );
      if (await f.exists()) {
        try {
          await f.copy('${f.path}.bak');
        } catch (e) {
          debugPrint('orbit: backup copy skipped: $e');
        }
      }
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('orbit save skipped: $e');
    }
  }

  // Setters below deliberately do NOT await the search. The forecast can take
  // seconds on a full catalogue, and awaiting it here left buttons stuck in
  // their busy state and snackbars queued up behind it. The UI watches
  // [searching] instead.

  Future<void> setSite(ObserverSite value) async {
    site = value;
    notifyListeners();
    await _save();
    unawaited(refresh());
  }

  Future<void> unlockPro() async {
    pro = true;
    windowDays = windowDays.clamp(1, maxWindowDays);
    notifyListeners();
    await _save();
    unawaited(refresh());
  }

  Future<void> setWindowDays(int days) async {
    windowDays = days.clamp(1, maxWindowDays);
    notifyListeners();
    await _save();
    unawaited(refresh());
  }

  Future<void> setIncludeDarkPasses(bool value) async {
    includeDarkPasses = value;
    notifyListeners();
    await _save();
    unawaited(refresh());
  }

  /// Result of a paste-import, so the UI can say exactly what happened instead
  /// of a vague "done". [needPro] counts newly added targets that the free tier
  /// will not actually track — claiming an import worked and then showing an
  /// unchanged forecast is the kind of thing that reads as a broken app.
  ({int parsed, int added, int updated, int rejected, int needPro, String? error})
      importTle(String text) {
    if (text.length > maxImportBytes) {
      return (
        parsed: 0,
        added: 0,
        updated: 0,
        rejected: 0,
        needPro: 0,
        error: tr(
          zh: '这段文本太大了(${(text.length / 1024).round()} KB)。请只粘贴肉眼可见卫星那一组,不要整份目录。',
          en: 'That text is too large (${(text.length / 1024).round()} KB). Paste the visible-satellite group rather than a whole catalogue.',
        )
      );
    }

    final incoming = Tle.parseAll(text);
    if (incoming.isEmpty) {
      return (
        parsed: 0,
        added: 0,
        updated: 0,
        rejected: 0,
        needPro: 0,
        error: null
      );
    }
    final nearEarth = incoming.where((t) => !t.isDeepSpace).toList();
    final rejected = incoming.length - nearEarth.length;

    final bundledIds = {for (final e in catalog) e.id};
    final freeIds = {for (final e in catalog) if (e.featured) e.id};

    // Merge into what was already imported rather than appending. Appending
    // meant every monthly refresh stored another full copy of the catalogue —
    // by the end of a year, a megabyte of duplicates re-parsed at every launch
    // and re-encoded on every settings change.
    final kept = <String, Tle>{};
    for (final t in Tle.parseAll(importedTleText)) {
      kept[t.satnum] = t;
    }
    var added = 0, updated = 0, needPro = 0;
    for (final t in nearEarth) {
      if (bundledIds.contains(t.satnum)) {
        updated++;
      } else {
        added++;
        if (!pro) needPro++;
      }
      final existing = kept[t.satnum];
      if (existing == null || t.epochJd >= existing.epochJd) {
        kept[t.satnum] = t;
      }
    }
    // Newly added objects the free tier cannot track are still stored: they
    // start working the moment Pro is unlocked.
    if (!pro) {
      needPro = nearEarth.where((t) => !freeIds.contains(t.satnum)).length;
    }

    final buffer = StringBuffer();
    for (final t in kept.values) {
      buffer.writeln(t.name);
      buffer.writeln(t.line1);
      buffer.writeln(t.line2);
    }
    importedTleText = buffer.toString();

    unawaited(_reloadCatalogAfterImport());
    return (
      parsed: nearEarth.length,
      added: added,
      updated: updated,
      rejected: rejected,
      needPro: needPro,
      error: null
    );
  }

  Future<void> _reloadCatalogAfterImport() async {
    // Two imports (or an import racing a clear) must not have the slower one
    // overwrite the newer catalogue after the fact.
    final token = ++_catalogToken;
    try {
      final bundled = await SatelliteCatalog.loadBundled();
      final imported = importedTleText.trim().isEmpty
          ? const <SatEntry>[]
          : SatelliteCatalog.parse(importedTleText, imported: true);
      if (token != _catalogToken) return;
      catalog = SatelliteCatalog.merge(bundled, imported);
      loadError = null;
    } catch (e) {
      debugPrint('orbit: catalog reload failed: $e');
      if (token != _catalogToken) return;
      loadError = tr(
        zh: '导入的数据没能装载进目录,预报仍在用之前的数据。',
        en: 'The imported data could not be loaded into the catalogue; the forecast is still using the previous elements.',
      );
    }
    notifyListeners();
    await _save();
    unawaited(refresh());
  }

  Future<void> clearImportedTle() async {
    importedTleText = '';
    await _reloadCatalogAfterImport();
  }

  /// Recomputes the whole forecast. Safe to call repeatedly — a newer call
  /// always wins and stale results are discarded.
  Future<void> refresh() async {
    final where = site;
    if (where == null || catalog.isEmpty) return;

    final token = ++_searchToken;
    searching = true;
    searchError = null;
    notifyListeners();

    final sats = trackable;
    final query = PassQuery(
      site: where,
      startUtc: DateTime.now().toUtc(),
      window: Duration(days: windowDays),
      minElevationDeg:
          pro && includeDarkPasses ? proMinElevation : defaultMinElevation,
      visibleOnly: !(pro && includeDarkPasses),
      maxResults: maxPasses,
    );

    try {
      final result = await compute(_searchInIsolate, {
        'tle': sats
            .map((e) => '${e.tle.name}\n${e.tle.line1}\n${e.tle.line2}')
            .join('\n'),
        'lat': where.latitude,
        'lon': where.longitude,
        'alt': where.altitudeKm,
        'startMs': query.startUtc.millisecondsSinceEpoch,
        'windowMs': query.window.inMilliseconds,
        'minEl': query.minElevationDeg,
        'visibleOnly': query.visibleOnly,
        'maxResults': query.maxResults,
      });
      if (token != _searchToken) return; // superseded
      passes = result.map((m) => SatPass.fromJson(m)).toList(growable: false);
      passesTruncated = passes.length >= maxPasses;
      lastSearchAt = DateTime.now();
    } catch (e) {
      if (token != _searchToken) return;
      // The isolate's error arrives as a RemoteError whose text is a Dart stack
      // trace — useful in the log, meaningless on screen.
      debugPrint('orbit search failed: $e');
      searchError = tr(
        zh: '过境计算失败了。可以下拉重试,或换一个观测点。',
        en: 'The pass computation failed. Pull down to retry, or try a different site.',
      );
      passes = const [];
      passesTruncated = false;
    } finally {
      if (token == _searchToken) {
        searching = false;
        notifyListeners();
      }
    }
  }

  /// True once the current forecast has aged out — the window it was computed
  /// for has started to run out from underneath it.
  bool get forecastIsStale {
    final at = lastSearchAt;
    if (at == null) return false;
    if (DateTime.now().difference(at) > const Duration(hours: 1)) return true;
    final first = passes.isEmpty ? null : passes.first;
    return first != null && first.end.isBefore(DateTime.now());
  }

  /// The next pass that has not started yet — the home screen's hero.
  SatPass? get nextPass {
    final now = DateTime.now();
    for (final p in passes) {
      if (p.end.isAfter(now)) return p;
    }
    return null;
  }
}

/// Isolate entry point. Takes and returns only plain values so it is safe on
/// every platform, and rebuilds the element sets from text rather than trying
/// to ship live objects across.
///
/// ⚠️ Contract: nothing reachable from here may call `tr()`, `isZhLocale`, or
/// otherwise touch `PlatformDispatcher` — a background isolate has no locale and
/// the lookup throws. That rules out `SatEntry.displayName` and
/// `SatelliteCatalog.merge` (which sorts by it) inside this function.
List<Map<String, dynamic>> _searchInIsolate(Map<String, dynamic> args) {
  final entries = SatelliteCatalog.parse(args['tle'] as String);
  final query = PassQuery(
    site: ObserverSite(
      latitude: args['lat'] as double,
      longitude: args['lon'] as double,
      altitudeKm: args['alt'] as double,
    ),
    startUtc:
        DateTime.fromMillisecondsSinceEpoch(args['startMs'] as int, isUtc: true),
    window: Duration(milliseconds: args['windowMs'] as int),
    minElevationDeg: args['minEl'] as double,
    visibleOnly: args['visibleOnly'] as bool,
    maxResults: args['maxResults'] as int,
  );
  return searchPasses(entries, query).map((p) => p.toJson()).toList();
}

/// Local stand-in for `dart:async`'s `unawaited`, kept here so the intent is
/// obvious at each call site: fire-and-forget persistence.
void unawaited(Future<void> future) {
  future.catchError((Object e) => debugPrint('orbit background task failed: $e'));
}
