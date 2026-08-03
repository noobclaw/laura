/// The pass finder.
///
/// The naive approach — step every 30 seconds and look at the elevation — costs
/// well over a million propagations for a full catalogue over ten days, which is
/// a stalled phone. The trick here is that the *sub-satellite point* cannot move
/// faster than the satellite's own mean motion plus the Earth's rotation, so
/// from any instant we can compute a provably safe jump: if the ground track is
/// 60 degrees away from the observer and can close at most 4.3 degrees a minute,
/// nothing can happen for the next fourteen minutes. Satellites spend the vast
/// majority of every orbit nowhere near you, so this collapses the search by
/// roughly an order of magnitude without ever skipping a pass.
///
/// Once a pass is detected, the boundaries come from bisection on elevation and
/// the culmination from a golden-section search, so the reported times are
/// second-accurate rather than snapped to the scan grid.
library;

import 'dart:math' as math;

import '../core/l10n.dart';
import 'astro.dart';
import 'models.dart';
import 'sgp4.dart';

/// Earth's rotation contribution to sub-point motion, degrees per minute.
const double _earthRotationDegPerMin = 360.0 / 1436.07;

/// Safety factor on the analytic ground-speed bound.
const double _stepSafety = 1.05;

/// Sun elevation above which a pass cannot possibly turn visible partway
/// through. The Sun moves at most ~0.25 deg/min, and no low-orbit pass lasts
/// longer than ~20 minutes, so anything higher than this stays daylight
/// throughout and can be skipped without refining.
const double _daylightSkipDeg = 8.0;

/// Inputs for one search. Kept to plain values so the whole thing can cross an
/// isolate boundary without ceremony.
class PassQuery {
  const PassQuery({
    required this.site,
    required this.startUtc,
    required this.window,
    this.minElevationDeg = 10.0,
    this.visibleOnly = true,
    this.maxResults = 300,
  });

  final ObserverSite site;
  final DateTime startUtc;
  final Duration window;

  /// Passes never reaching this elevation are not worth a notification-free
  /// user's time (and are usually blocked by buildings anyway).
  final double minElevationDeg;

  /// When true, only naked-eye passes are kept: satellite sunlit, observer's sky
  /// past civil twilight. Pro turns this off to include shadow passes.
  final bool visibleOnly;
  final int maxResults;
}

/// Upper bound on passes kept per satellite, so a pathological element set
/// cannot balloon memory. Ten days of a low orbit yields well under a hundred.
const int _perSatelliteCap = 400;

/// Finds every pass of [satellites] over the query's site and window.
///
/// Every satellite is always searched in full: the [PassQuery.maxResults] cap is
/// applied *after* sorting, so what gets dropped is the far end of the timeline
/// rather than an arbitrary tail of the catalogue. Capping during the sweep
/// would have silently excluded whole satellites — the list would look complete
/// while missing everything after the twentieth object in the catalogue.
List<SatPass> searchPasses(List<SatEntry> satellites, PassQuery query) {
  final out = <SatPass>[];
  final site = query.site;
  final siteEcef = observerEcef(site.latitude, site.longitude, site.altitudeKm);
  final startJd = julianDateOf(query.startUtc);
  final endJd = startJd + query.window.inMilliseconds / 86400000.0;

  for (final entry in satellites) {
    _passesForSatellite(
      entry: entry,
      query: query,
      siteEcef: siteEcef,
      startJd: startJd,
      endJd: endJd,
      sink: out,
    );
  }

  out.sort((a, b) => a.start.compareTo(b.start));
  if (out.length > query.maxResults) {
    return out.sublist(0, query.maxResults);
  }
  return out;
}

/// Evaluated geometry at one instant, reused across the scan and the refiners.
class _Fix {
  _Fix(this.elevationDeg, this.azimuthDeg, this.rangeKm, this.centralAngleDeg,
      this.reachDeg, this.satEcef);
  final double elevationDeg, azimuthDeg, rangeKm;
  final double centralAngleDeg, reachDeg;
  final Vec3 satEcef;

  /// Positive inside the pass, negative outside — the function both the scan and
  /// the bisection agree on.
  double get margin => reachDeg - centralAngleDeg;
}

void _passesForSatellite({
  required SatEntry entry,
  required PassQuery query,
  required Vec3 siteEcef,
  required double startJd,
  required double endJd,
  required List<SatPass> sink,
}) {
  final sat = Sgp4Satellite(entry.tle);
  if (!sat.usable) return;

  final site = query.site;
  final minEl = query.minElevationDeg;

  // Latitude reachability: a satellite's ground track never leaves +/- its
  // inclination, so an observer further poleward than that plus the horizon
  // radius can never see it. Cheap, and it removes whole swathes of the
  // catalogue for anyone outside the tropics.
  final incDeg = entry.tle.inclo * radToDeg;
  final trackLimit = incDeg <= 90.0 ? incDeg : 180.0 - incDeg;
  final nRadPerSec = entry.tle.noKozai / 60.0;
  final semiMajorKm =
      math.pow(Wgs72.mu / (nRadPerSec * nRadPerSec), 1.0 / 3.0).toDouble();
  final apogeeAltKm = semiMajorKm * (1.0 + entry.tle.ecco) - earthRadiusKm;
  if (apogeeAltKm <= 0) return;
  final maxReachDeg = visibilityRadiusDeg(apogeeAltKm, minEl);
  if (site.latitude.abs() > trackLimit + maxReachDeg + 1.0) return;

  // Provable bound on how fast the ground track can approach the observer.
  final groundRateDegPerMin =
      (entry.tle.noKozai * radToDeg + _earthRotationDegPerMin) * _stepSafety;

  final epochJd = entry.tle.epochJd;

  _Fix? fixAt(double jd) {
    final state = sat.propagate((jd - epochJd) * 1440.0);
    if (state == null) return null;
    final gmst = gmstRadians(jd);
    final ecef = temeToEcef(Vec3(state.x, state.y, state.z), gmst);
    final gp = subPoint(ecef);
    final look = lookAngles(ecef, siteEcef, site.latitude, site.longitude);
    return _Fix(
      look.elevationDeg,
      look.azimuthDeg,
      look.rangeKm,
      centralAngleDeg(site.latitude, site.longitude, gp.latDeg, gp.lonDeg),
      visibilityRadiusDeg(gp.altKm, minEl),
      ecef,
    );
  }

  const oneMinute = 1.0 / 1440.0;
  final capForThisSatellite = sink.length + _perSatelliteCap;
  var jd = startJd;
  double? previousOutsideJd;

  while (jd < endJd) {
    if (sink.length >= capForThisSatellite) return;
    final fix = fixAt(jd);
    if (fix == null) return; // decayed mid-window — stop this satellite

    if (fix.margin < 0) {
      previousOutsideJd = jd;
      final stepMin = math.max(0.25, -fix.margin / groundRateDegPerMin);
      jd += stepMin * oneMinute;
      continue;
    }

    // Inside a pass. If the observer is in broad daylight there is nothing to
    // see and nothing worth refining — inch forward until the pass is over.
    if (query.visibleOnly) {
      final sunEl = sunElevationDeg(
          jd, site.latitude, site.longitude, site.altitudeKm);
      if (sunEl > _daylightSkipDeg) {
        previousOutsideJd = null;
        jd += 2.0 * oneMinute;
        continue;
      }
    }

    // Normally the previous scan step is a ready-made bracket. It is missing in
    // two cases: the search window opened with the pass already under way, and
    // the daylight skip walked us into the middle of one as the sky darkened.
    // Reporting the current instant as "rises" there would put a mid-sky bearing
    // under the word "rises" — right when dusk passes, the best ones, happen.
    final riseJd = previousOutsideJd == null
        ? _backtrackToRise(fixAt, jd, startJd)
        : _bisectMargin(fixAt, previousOutsideJd, jd);

    // Walk out of the pass to bracket the set, then bisect.
    var probe = jd;
    var lastInside = jd;
    var setJd = endJd;
    while (probe < endJd) {
      probe += 0.5 * oneMinute;
      final f = fixAt(probe);
      if (f == null || f.margin < 0) {
        setJd = f == null ? lastInside : _bisectMargin(fixAt, probe, lastInside);
        break;
      }
      lastInside = probe;
    }
    if (setJd <= riseJd) {
      jd = lastInside + oneMinute;
      previousOutsideJd = null;
      continue;
    }

    final pass = _buildPass(
      entry: entry,
      sat: sat,
      query: query,
      siteEcef: siteEcef,
      riseJd: riseJd,
      setJd: setJd,
      fixAt: fixAt,
    );
    if (pass != null) sink.add(pass);

    jd = setJd + oneMinute;
    previousOutsideJd = null;
  }
}

/// Walks backwards from a point known to be inside a pass until it drops out of
/// it, then bisects. Bounded by the start of the search window, so a pass that
/// genuinely began before the window is still reported from the window edge.
double _backtrackToRise(
  _Fix? Function(double) fixAt,
  double insideJd,
  double floorJd,
) {
  const step = 0.5 / 1440.0; // 30 seconds
  var probe = insideJd;
  for (var i = 0; i < 60; i++) {
    final next = probe - step;
    if (next <= floorJd) return floorJd;
    final f = fixAt(next);
    if (f == null) return probe;
    if (f.margin < 0) return _bisectMargin(fixAt, next, probe);
    probe = next;
  }
  return probe;
}

/// Bisects the in-pass margin between an outside instant and an inside instant.
/// Twenty halvings take a 30-second bracket down to well under a millisecond;
/// the limiting factor on reported times is the element set, not this.
double _bisectMargin(
  _Fix? Function(double) fixAt,
  double outsideJd,
  double insideJd,
) {
  var lo = outsideJd;
  var hi = insideJd;
  for (var i = 0; i < 20; i++) {
    final mid = (lo + hi) / 2.0;
    final f = fixAt(mid);
    if (f == null || f.margin < 0) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return hi;
}

/// Golden-section maximisation of elevation across the pass. Elevation is
/// unimodal between rise and set for any near-Earth orbit, so this converges
/// cleanly and beats sampling the grid for the peak.
double _findCulmination(
  _Fix? Function(double) fixAt,
  double loJd,
  double hiJd,
) {
  const invPhi = 0.6180339887498949;
  var a = loJd, b = hiJd;
  var c = b - (b - a) * invPhi;
  var d = a + (b - a) * invPhi;
  var fc = fixAt(c)?.elevationDeg ?? -90.0;
  var fd = fixAt(d)?.elevationDeg ?? -90.0;
  for (var i = 0; i < 30; i++) {
    if (fc > fd) {
      b = d;
      d = c;
      fd = fc;
      c = b - (b - a) * invPhi;
      fc = fixAt(c)?.elevationDeg ?? -90.0;
    } else {
      a = c;
      c = d;
      fc = fd;
      d = a + (b - a) * invPhi;
      fd = fixAt(d)?.elevationDeg ?? -90.0;
    }
  }
  return (a + b) / 2.0;
}

/// Number of points sampled along a pass for the sky-dome curve. Enough for a
/// smooth arc, few enough that a full-catalogue search stays responsive.
const int _trackSamples = 24;

SatPass? _buildPass({
  required SatEntry entry,
  required Sgp4Satellite sat,
  required PassQuery query,
  required Vec3 siteEcef,
  required double riseJd,
  required double setJd,
  required _Fix? Function(double) fixAt,
}) {
  final site = query.site;
  final peakJd = _findCulmination(fixAt, riseJd, setJd);

  final riseFix = fixAt(riseJd);
  final setFix = fixAt(setJd);
  final peakFix = fixAt(peakJd);
  if (riseFix == null || setFix == null || peakFix == null) return null;

  final track = <PassSample>[];
  var anyVisible = false;
  var anyLitAboveHorizon = false;
  double? brightest;

  for (var i = 0; i < _trackSamples; i++) {
    final jd = riseJd + (setJd - riseJd) * i / (_trackSamples - 1);
    final f = fixAt(jd);
    if (f == null) continue;
    final sunEcef = temeToEcef(sunPositionEci(jd), gmstRadians(jd));
    final lit = isSunlit(f.satEcef, sunEcef);
    final sunEl =
        lookAngles(sunEcef, siteEcef, site.latitude, site.longitude).elevationDeg;
    final mag = apparentMagnitude(
      standardMagnitude: entry.standardMagnitude,
      satEci: f.satEcef,
      sunEci: sunEcef,
      observerEci: siteEcef,
      rangeKm: f.rangeKm,
    );
    if (lit && f.elevationDeg > 0) anyLitAboveHorizon = true;
    final visibleNow = lit && sunEl < -6.0 && f.elevationDeg > 0;
    if (visibleNow) {
      anyVisible = true;
      if (mag != null && (brightest == null || mag < brightest)) brightest = mag;
    }
    track.add(PassSample(
      time: dateTimeFromJulian(jd).toLocal(),
      azimuthDeg: f.azimuthDeg,
      elevationDeg: f.elevationDeg,
      rangeKm: f.rangeKm,
      sunlit: lit,
      magnitude: mag,
    ));
  }

  if (track.isEmpty) return null;
  if (query.visibleOnly && !anyVisible) return null;

  final curated = curatedSatellites[entry.tle.satnum];
  return SatPass(
    satId: entry.tle.satnum,
    satName: entry.tle.name,
    satNameZh: entry.nameZh ?? curated?.zh,
    start: dateTimeFromJulian(riseJd).toLocal(),
    peak: dateTimeFromJulian(peakJd).toLocal(),
    end: dateTimeFromJulian(setJd).toLocal(),
    startAzimuth: riseFix.azimuthDeg,
    peakAzimuth: peakFix.azimuthDeg,
    endAzimuth: setFix.azimuthDeg,
    peakElevation: peakFix.elevationDeg,
    peakRangeKm: peakFix.rangeKm,
    visibility: anyVisible
        ? PassVisibility.visible
        : (anyLitAboveHorizon
            ? PassVisibility.daylight
            : PassVisibility.eclipsed),
    brightestMagnitude: brightest,
    track: track,
  );
}

/// Compass point for an azimuth, in the user's language. Sixteen points is the
/// resolution people can actually act on when told where to look.
String compassPoint(double azimuthDeg) {
  const zh = [
    '北', '北东北', '东北', '东东北', '东', '东东南', '东南', '南东南',
    '南', '南西南', '西南', '西西南', '西', '西西北', '西北', '北西北',
  ];
  const en = [
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
  ];
  var a = azimuthDeg % 360.0;
  if (a < 0) a += 360.0;
  final index = ((a + 11.25) ~/ 22.5) % 16;
  return isZhLocale ? zh[index] : en[index];
}
