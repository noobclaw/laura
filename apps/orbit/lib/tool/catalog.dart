import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';
import 'sgp4.dart';

/// The satellite catalogue: a snapshot bundled with the app plus whatever the
/// user has pasted in since.
///
/// Provenance of the bundled file (`assets/tle/visual.txt`): CelesTrak's
/// `visual` group — the objects bright enough to see without optics — captured
/// at epoch 2026-08-02, filtered to near-Earth orbits only. The underlying
/// element sets are produced by the US Space Force and are US Government works,
/// not subject to copyright. Nothing here ever touches the network; refreshing
/// is a paste, not a fetch. See PLAN.md for the full licensing note.
class SatelliteCatalog {
  const SatelliteCatalog._(this.entries);

  final List<SatEntry> entries;

  static const String bundledAssetPath = 'assets/tle/visual.txt';

  /// The date the bundled snapshot was captured, for the "how old is this"
  /// banner when a user has never imported anything.
  static final DateTime bundledEpoch = DateTime.utc(2026, 8, 2);

  /// Parses element sets out of arbitrary text. Deep-space objects are rejected
  /// here rather than in the UI: SGP4's near-Earth branch would silently produce
  /// garbage for them, and a wrong prediction is worse than a missing one.
  static List<SatEntry> parse(String text, {bool imported = false}) {
    final out = <SatEntry>[];
    for (final tle in Tle.parseAll(text)) {
      if (tle.isDeepSpace) continue;
      final curated = curatedSatellites[tle.satnum];
      out.add(SatEntry(
        tle: tle,
        nameZh: curated?.zh,
        standardMagnitude: curated?.mag,
        featured: curated?.featured ?? false,
        imported: imported,
      ));
    }
    return out;
  }

  static Future<List<SatEntry>> loadBundled() async {
    final text = await rootBundle.loadString(bundledAssetPath);
    return parse(text);
  }

  /// Bundled snapshot merged with the user's imports. When both carry the same
  /// object, the newer element set wins — that is the whole point of importing.
  static List<SatEntry> merge(List<SatEntry> bundled, List<SatEntry> imported) {
    final byId = <String, SatEntry>{};
    for (final e in bundled) {
      byId[e.id] = e;
    }
    for (final e in imported) {
      final existing = byId[e.id];
      if (existing == null || e.tle.epochJd >= existing.tle.epochJd) {
        // Keep the curated name/brightness even when the elements are replaced.
        final curated = curatedSatellites[e.id];
        byId[e.id] = SatEntry(
          tle: e.tle,
          nameZh: curated?.zh ?? existing?.nameZh,
          standardMagnitude: curated?.mag ?? existing?.standardMagnitude,
          featured: curated?.featured ?? existing?.featured ?? false,
          imported: true,
        );
      }
    }
    final list = byId.values.toList();
    list.sort((a, b) {
      if (a.featured != b.featured) return a.featured ? -1 : 1;
      return a.displayName.compareTo(b.displayName);
    });
    return list;
  }

  /// What the free tier can track: the named headliners everyone has heard of.
  static List<SatEntry> freeTier(List<SatEntry> all) =>
      all.where((e) => e.featured).toList();

  /// Newest element epoch across a catalogue, as an age in days.
  static double newestAgeDays(List<SatEntry> all, DateTime now) {
    if (all.isEmpty) return double.infinity;
    var newest = all.first.tle.epochJd;
    for (final e in all) {
      if (e.tle.epochJd > newest) newest = e.tle.epochJd;
    }
    return julianDateOf(now) - newest;
  }

  /// Median element age — a fairer summary than the newest when a user has
  /// imported one fresh object into an otherwise old catalogue.
  static double medianAgeDays(List<SatEntry> all, DateTime now) {
    if (all.isEmpty) return double.infinity;
    final nowJd = julianDateOf(now);
    final ages = all.map((e) => nowJd - e.tle.epochJd).toList()..sort();
    return ages[ages.length ~/ 2];
  }
}
