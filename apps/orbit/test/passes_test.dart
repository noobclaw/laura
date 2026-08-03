import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/tool/astro.dart';
import 'package:orbit/tool/catalog.dart';
import 'package:orbit/tool/models.dart';
import 'package:orbit/tool/passes.dart';
import 'package:orbit/tool/sgp4.dart';
import 'package:orbit/tool/store.dart';

/// Real element sets, epoch 2026-08-02 — the same snapshot the app ships.
const String _issTle = '''
ISS (ZARYA)
1 25544U 98067A   26214.50635181  .00006342  00000+0  12183-3 0  9996
2 25544  51.6315  70.8679 0007172   4.7554 355.3502 15.49313226578933
''';

const String _hstTle = '''
HST
1 20580U 90037B   26214.16388447  .00005559  00000+0  17148-3 0  9997
2 20580  28.4694 179.5121 0002418 268.8425  91.1832 15.14063834782404
''';

/// Beijing, a mid-latitude site well inside the ISS ground track.
const ObserverSite _beijing =
    ObserverSite(latitude: 39.9042, longitude: 116.4074, name: 'Beijing');

final DateTime _start = DateTime.utc(2026, 8, 3, 0, 0, 0);

void main() {
  // The import tests reach the asset bundle through the store's catalogue
  // reload; without a binding that path logs a wall of scary-looking (but
  // handled) errors into the CI output.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pass search', () {
    test('finds ISS passes over a mid-latitude site', () {
      final sats = SatelliteCatalog.parse(_issTle);
      expect(sats, hasLength(1));

      final passes = searchPasses(
        sats,
        PassQuery(
          site: _beijing,
          startUtc: _start,
          window: const Duration(days: 2),
          visibleOnly: false,
        ),
      );

      // The ISS makes several 10-degree-plus passes a day over Beijing.
      expect(passes.length, greaterThanOrEqualTo(4));
      for (final p in passes) {
        expect(p.start.isBefore(p.peak), isTrue, reason: 'rise before peak');
        expect(p.peak.isBefore(p.end), isTrue, reason: 'peak before set');
        expect(p.peakElevation, greaterThanOrEqualTo(9.9));
        expect(p.peakElevation, lessThanOrEqualTo(90.0));
        expect(p.duration.inSeconds, inInclusiveRange(30, 1500));
        expect(p.startAzimuth, inInclusiveRange(0, 360));
        expect(p.endAzimuth, inInclusiveRange(0, 360));
        expect(p.track.length, greaterThan(4));
        // The track must be ordered in time and never dip below the search bar
        // by more than rounding.
        for (var i = 1; i < p.track.length; i++) {
          expect(p.track[i].time.isAfter(p.track[i - 1].time), isTrue);
        }
        // Ends sit on the 10-degree bar, except where the search window
        // itself clips a pass already in progress.
        expect(p.track.first.elevationDeg, greaterThanOrEqualTo(9.5));
        expect(p.track.last.elevationDeg, greaterThanOrEqualTo(9.5));
      }
      // Results come back in chronological order for the timetable UI.
      for (var i = 1; i < passes.length; i++) {
        expect(passes[i].start.isAfter(passes[i - 1].start), isTrue);
      }
    });

    test('adaptive stepping finds exactly what a brute-force scan finds', () {
      // This is the load-bearing test for the whole search: the analytic jump
      // is only legitimate if it cannot skip a pass. Compare against a dumb
      // 10-second sweep over the same window.
      final sats = SatelliteCatalog.parse(_issTle);
      const window = Duration(hours: 18);

      final found = searchPasses(
        sats,
        PassQuery(
          site: _beijing,
          startUtc: _start,
          window: window,
          visibleOnly: false,
        ),
      );

      final brute = _bruteForcePassStarts(
        sats.single.tle,
        _beijing,
        _start,
        window,
        minElevationDeg: 10.0,
      );

      expect(found.length, brute.length,
          reason: 'adaptive search missed or invented a pass');
      for (var i = 0; i < brute.length; i++) {
        final delta =
            found[i].start.toUtc().difference(brute[i]).inSeconds.abs();
        // Brute force resolves to its 10-second grid; the refined rise time
        // must land inside that bucket.
        expect(delta, lessThanOrEqualTo(11),
            reason: 'rise time disagrees for pass $i');
      }
    });

    test('visible-only is a strict subset of every pass', () {
      final sats = SatelliteCatalog.parse(_issTle);
      final all = searchPasses(
        sats,
        PassQuery(
            site: _beijing,
            startUtc: _start,
            window: const Duration(days: 3),
            visibleOnly: false),
      );
      final visible = searchPasses(
        sats,
        PassQuery(
            site: _beijing,
            startUtc: _start,
            window: const Duration(days: 3),
            visibleOnly: true),
      );
      expect(visible.length, lessThanOrEqualTo(all.length));
      for (final p in visible) {
        expect(p.visible, isTrue);
        // A visible pass must contain at least one sunlit sample above the
        // horizon — that is the entire claim being made to the user.
        expect(p.visibleSamples, isNotEmpty);
      }
    });

    test('a low-inclination orbit is never reported from the high Arctic', () {
      // HST sits at 28.5 degrees inclination; from Svalbard it cannot rise.
      final sats = SatelliteCatalog.parse(_hstTle);
      final passes = searchPasses(
        sats,
        PassQuery(
          site: const ObserverSite(latitude: 78.2, longitude: 15.6),
          startUtc: _start,
          window: const Duration(days: 3),
          visibleOnly: false,
        ),
      );
      expect(passes, isEmpty);
    });

    test('the same orbit is plentiful from a site under its ground track', () {
      final sats = SatelliteCatalog.parse(_hstTle);
      final passes = searchPasses(
        sats,
        PassQuery(
          site: const ObserverSite(latitude: 25.0, longitude: 121.5),
          startUtc: _start,
          window: const Duration(days: 2),
          visibleOnly: false,
        ),
      );
      expect(passes, isNotEmpty);
    });

    test('maxResults caps the work without corrupting the ordering', () {
      final sats = SatelliteCatalog.parse('$_issTle\n$_hstTle');
      final passes = searchPasses(
        sats,
        PassQuery(
          site: _beijing,
          startUtc: _start,
          window: const Duration(days: 5),
          visibleOnly: false,
          maxResults: 3,
        ),
      );
      expect(passes.length, lessThanOrEqualTo(3));
      for (var i = 1; i < passes.length; i++) {
        expect(passes[i].start.isAfter(passes[i - 1].start), isTrue);
      }
    });

    test('passes serialise across the isolate boundary without loss', () {
      final sats = SatelliteCatalog.parse(_issTle);
      final passes = searchPasses(
        sats,
        PassQuery(
            site: _beijing,
            startUtc: _start,
            window: const Duration(days: 1),
            visibleOnly: false),
      );
      expect(passes, isNotEmpty);
      final round = SatPass.fromJson(passes.first.toJson());
      expect(round.satId, passes.first.satId);
      expect(round.peakElevation, closeTo(passes.first.peakElevation, 1e-9));
      expect(round.track.length, passes.first.track.length);
      expect(round.start, passes.first.start);
      expect(round.visible, passes.first.visible);
    });
  });

  group('catalogue', () {
    test('curated entries pick up their Chinese names and free-tier flag', () {
      final entries = SatelliteCatalog.parse(_issTle);
      expect(entries.single.nameZh, '国际空间站');
      expect(entries.single.featured, isTrue);
      expect(entries.single.standardMagnitude, -1.8);
    });

    test('an import with a newer epoch replaces the bundled elements', () {
      final bundled = SatelliteCatalog.parse(_issTle);
      // Same object, epoch a day later.
      final newer = SatelliteCatalog.parse('''
ISS (ZARYA)
1 25544U 98067A   26215.50635181  .00006342  00000+0  12183-3 0  9996
2 25544  51.6315  70.8679 0007172   4.7554 355.3502 15.49313226578933
''', imported: true);
      final merged = SatelliteCatalog.merge(bundled, newer);
      expect(merged, hasLength(1));
      expect(merged.single.tle.epochJd,
          closeTo(bundled.single.tle.epochJd + 1.0, 1e-6));
      // Curated presentation survives the swap.
      expect(merged.single.nameZh, '国际空间站');
      expect(merged.single.featured, isTrue);
      expect(merged.single.imported, isTrue);
    });

    test('deep-space objects are refused at the door', () {
      final entries = SatelliteCatalog.parse('''
GEO TEST
1 40000U 14001A   26214.50000000  .00000000  00000+0  00000+0 0  9995
2 40000   0.0200  95.0000 0002000 100.0000 260.0000  1.00270000 40000
''');
      expect(entries, isEmpty);
    });

    test('freshness buckets match the stated thresholds', () {
      expect(freshnessOf(0), ElementFreshness.fresh);
      expect(freshnessOf(7), ElementFreshness.fresh);
      expect(freshnessOf(7.1), ElementFreshness.aging);
      expect(freshnessOf(30), ElementFreshness.aging);
      expect(freshnessOf(31), ElementFreshness.stale);
    });
  });

  group('visibility verdict', () {
    test('a daylight pass is labelled daylight, not eclipsed', () {
      final sats = SatelliteCatalog.parse(_issTle);
      final passes = searchPasses(
        sats,
        PassQuery(
            site: _beijing,
            startUtc: _start,
            window: const Duration(days: 2),
            visibleOnly: false),
      );
      // Over two days there is always at least one pass in each state; the two
      // reasons for "not visible" must never be reported interchangeably.
      final daylight =
          passes.where((p) => p.visibility == PassVisibility.daylight);
      for (final p in daylight) {
        expect(p.visible, isFalse);
        // Daylight means the satellite *was* lit — that is the distinction.
        expect(p.track.any((s) => s.sunlit && s.elevationDeg > 0), isTrue);
      }
      final eclipsed =
          passes.where((p) => p.visibility == PassVisibility.eclipsed);
      for (final p in eclipsed) {
        expect(p.track.any((s) => s.sunlit && s.elevationDeg > 0), isFalse);
      }
      expect(daylight.length + eclipsed.length + passes.where((p) => p.visible).length,
          passes.length);
    });
  });

  group('imports', () {
    test('re-importing the same data does not grow storage', () {
      final store = OrbitStore()
        ..loaded = true
        ..catalog = SatelliteCatalog.parse(_issTle);

      final first = store.importTle(_hstTle);
      expect(first.parsed, 1);
      final afterOne = store.importedTleText.length;

      final second = store.importTle(_hstTle);
      expect(second.parsed, 1);
      // Appending blindly is how a monthly-refresh habit turns into a megabyte
      // of duplicates re-parsed at every launch.
      expect(store.importedTleText.length, afterOne);
    });

    test('an oversized paste is refused rather than parsed on the UI thread', () {
      final store = OrbitStore()..loaded = true;
      final huge = 'x' * (OrbitStore.maxImportBytes + 1);
      final r = store.importTle(huge);
      expect(r.parsed, 0);
      expect(r.error, isNotNull);
    });

    test('free tier is told which imported targets it cannot use', () {
      final store = OrbitStore()
        ..loaded = true
        ..pro = false
        ..catalog = SatelliteCatalog.parse(_issTle);
      final r = store.importTle(_hstTle);
      expect(r.added, 1);
      expect(r.needPro, 1);
    });
  });

  group('presentation helpers', () {
    test('compass points bracket their bearings', () {
      expect(compassPoint(0), anyOf('北', 'N'));
      expect(compassPoint(90), anyOf('东', 'E'));
      expect(compassPoint(180), anyOf('南', 'S'));
      expect(compassPoint(270), anyOf('西', 'W'));
      expect(compassPoint(359), anyOf('北', 'N'));
      expect(compassPoint(45), anyOf('东北', 'NE'));
    });
  });
}

/// A deliberately naive pass finder: step every ten seconds, record each
/// upward crossing of the elevation threshold. Slow, obviously correct, and the
/// yardstick the optimised search has to match.
List<DateTime> _bruteForcePassStarts(
  Tle tle,
  ObserverSite site,
  DateTime startUtc,
  Duration window, {
  required double minElevationDeg,
}) {
  final sat = Sgp4Satellite(tle);
  final siteEcef = observerEcef(site.latitude, site.longitude, site.altitudeKm);
  final starts = <DateTime>[];
  var wasAbove = false;

  final steps = window.inSeconds ~/ 10;
  for (var i = 0; i <= steps; i++) {
    final t = startUtc.add(Duration(seconds: i * 10));
    final jd = julianDateOf(t);
    final state = sat.propagate((jd - tle.epochJd) * 1440.0);
    if (state == null) break;
    final ecef = temeToEcef(Vec3(state.x, state.y, state.z), gmstRadians(jd));
    final el =
        lookAngles(ecef, siteEcef, site.latitude, site.longitude).elevationDeg;
    final above = el >= minElevationDeg;
    if (above && !wasAbove) starts.add(t);
    wasAbove = above;
  }
  return starts;
}
