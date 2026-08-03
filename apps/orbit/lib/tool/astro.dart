/// Frame transforms and the bits of astronomy a pass predictor needs: where the
/// satellite is relative to *you*, whether sunlight is still hitting it, and
/// whether your own sky is dark enough to see it. All closed-form, all local.
library;

import 'dart:math' as math;

import 'sgp4.dart';

const double degToRad = math.pi / 180.0;
const double radToDeg = 180.0 / math.pi;
const double _twoPi = math.pi * 2.0;

/// WGS-84 figure of the Earth, used for the observer's own position. (The
/// satellite side stays on WGS-72 because that is what SGP4 is fitted to; the
/// two ellipsoids differ by a couple of metres, far under TLE noise.)
const double earthRadiusKm = 6378.137;
const double _flattening = 1.0 / 298.257223563;

/// Greenwich Mean Sidereal Time in radians (IAU-82 series). Turns "when" into
/// "how far the Earth has spun", which is the whole of the TEME->Earth-fixed
/// transform for our purposes.
double gmstRadians(double julianDate) {
  final t = (julianDate - 2451545.0) / 36525.0;
  var secs = -6.2e-6 * t * t * t +
      0.093104 * t * t +
      (876600.0 * 3600.0 + 8640184.812866) * t +
      67310.54841;
  // 240 seconds of sidereal time per degree.
  var rad = (secs / 240.0) * degToRad % _twoPi;
  if (rad < 0) rad += _twoPi;
  return rad;
}

/// A cartesian vector in kilometres.
class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;

  double get length => math.sqrt(x * x + y * y + z * z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 get unit {
    final l = length;
    return l == 0 ? const Vec3(0, 0, 0) : Vec3(x / l, y / l, z / l);
  }
}

/// TEME (the frame SGP4 outputs) to Earth-fixed, by rotating through GMST.
Vec3 temeToEcef(Vec3 teme, double gmst) {
  final c = math.cos(gmst);
  final s = math.sin(gmst);
  return Vec3(teme.x * c + teme.y * s, -teme.x * s + teme.y * c, teme.z);
}

/// The observer's Earth-fixed position from geodetic coordinates.
Vec3 observerEcef(double latDeg, double lonDeg, double altKm) {
  final lat = latDeg * degToRad;
  final lon = lonDeg * degToRad;
  final e2 = _flattening * (2.0 - _flattening);
  final sinLat = math.sin(lat);
  final n = earthRadiusKm / math.sqrt(1.0 - e2 * sinLat * sinLat);
  return Vec3(
    (n + altKm) * math.cos(lat) * math.cos(lon),
    (n + altKm) * math.cos(lat) * math.sin(lon),
    (n * (1.0 - e2) + altKm) * sinLat,
  );
}

/// Where a satellite appears in your sky.
class LookAngles {
  const LookAngles(this.azimuthDeg, this.elevationDeg, this.rangeKm);

  /// Compass bearing, 0 = true north, increasing clockwise.
  final double azimuthDeg;

  /// Degrees above the horizon; negative means below it.
  final double elevationDeg;
  final double rangeKm;
}

/// Earth-fixed target -> topocentric look angles for an observer.
LookAngles lookAngles(Vec3 targetEcef, Vec3 siteEcef, double latDeg, double lonDeg) {
  final lat = latDeg * degToRad;
  final lon = lonDeg * degToRad;
  final d = targetEcef - siteEcef;

  final sinLat = math.sin(lat), cosLat = math.cos(lat);
  final sinLon = math.sin(lon), cosLon = math.cos(lon);

  final south = sinLat * cosLon * d.x + sinLat * sinLon * d.y - cosLat * d.z;
  final east = -sinLon * d.x + cosLon * d.y;
  final zenith = cosLat * cosLon * d.x + cosLat * sinLon * d.y + sinLat * d.z;

  final range = d.length;
  final elevation = range == 0 ? 0.0 : math.asin(zenith / range) * radToDeg;
  var azimuth = math.atan2(east, -south) * radToDeg;
  if (azimuth < 0) azimuth += 360.0;
  return LookAngles(azimuth, elevation, range);
}

/// Sub-satellite point: the spot on the ground the satellite is directly over,
/// plus its height. Used by the pass search to bound how fast the geometry can
/// possibly change.
class GroundPoint {
  const GroundPoint(this.latDeg, this.lonDeg, this.altKm);
  final double latDeg, lonDeg, altKm;
}

GroundPoint subPoint(Vec3 ecef) {
  final e2 = _flattening * (2.0 - _flattening);
  final r = math.sqrt(ecef.x * ecef.x + ecef.y * ecef.y);
  var lat = math.atan2(ecef.z, r);
  var c = 1.0;
  // Converges in a handful of passes for any near-Earth orbit.
  for (var i = 0; i < 6; i++) {
    final sinLat = math.sin(lat);
    c = 1.0 / math.sqrt(1.0 - e2 * sinLat * sinLat);
    lat = math.atan2(ecef.z + earthRadiusKm * c * e2 * sinLat, r);
  }
  final sinLat = math.sin(lat);
  final alt = r / math.cos(lat) - earthRadiusKm * c;
  var lon = math.atan2(ecef.y, ecef.x) * radToDeg;
  if (lon > 180) lon -= 360;
  if (lon < -180) lon += 360;
  // Guard the polar case where cos(lat) collapses.
  final altSafe = lat.abs() > 1.5533
      ? (ecef.z.abs() / sinLat.abs()) - earthRadiusKm * c * (1 - e2)
      : alt;
  return GroundPoint(lat * radToDeg, lon, altSafe);
}

/// Great-circle separation between two ground points, in degrees.
double centralAngleDeg(double lat1, double lon1, double lat2, double lon2) {
  final p1 = lat1 * degToRad, p2 = lat2 * degToRad;
  final dp = (lat2 - lat1) * degToRad;
  final dl = (lon2 - lon1) * degToRad;
  final a = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a)) * radToDeg;
}

/// The largest great-circle distance from the sub-point at which a satellite of
/// height [altKm] still sits at least [elevationDeg] above the horizon. The pass
/// search uses this to jump time forward safely instead of crawling minute by
/// minute through the ~93% of the orbit that is nowhere near the observer.
double visibilityRadiusDeg(double altKm, double elevationDeg) {
  final e = elevationDeg * degToRad;
  final ratio = earthRadiusKm * math.cos(e) / (earthRadiusKm + altKm);
  if (ratio >= 1.0) return 0.0;
  return (math.acos(ratio) - e) * radToDeg;
}

/// Geocentric position of the Sun in the same (TEME-ish) frame SGP4 uses, in km.
/// Low-precision series — good to about 0.01 degrees, which is three orders of
/// magnitude better than this app needs for "is it lit / is it dark".
Vec3 sunPositionEci(double julianDate) {
  final t = (julianDate - 2451545.0) / 36525.0;
  final meanLong = (280.460 + 36000.77 * t) % 360.0;
  final meanAnomaly = ((357.5277233 + 35999.05034 * t) % 360.0) * degToRad;
  final eclipticLong = (meanLong +
          1.914666471 * math.sin(meanAnomaly) +
          0.019994643 * math.sin(2.0 * meanAnomaly)) *
      degToRad;
  final obliquity = (23.439291 - 0.0130042 * t) * degToRad;
  final distanceAu = 1.000140612 -
      0.016708617 * math.cos(meanAnomaly) -
      0.000139589 * math.cos(2.0 * meanAnomaly);
  const au = 149597870.7;
  final r = distanceAu * au;
  return Vec3(
    r * math.cos(eclipticLong),
    r * math.cos(obliquity) * math.sin(eclipticLong),
    r * math.sin(obliquity) * math.sin(eclipticLong),
  );
}

/// Sun elevation for an observer, in degrees. Below -6 is civil twilight: dark
/// enough that a sunlit satellite actually stands out.
double sunElevationDeg(
  double julianDate,
  double latDeg,
  double lonDeg,
  double altKm,
) {
  final gmst = gmstRadians(julianDate);
  final sunEcef = temeToEcef(sunPositionEci(julianDate), gmst);
  final site = observerEcef(latDeg, lonDeg, altKm);
  return lookAngles(sunEcef, site, latDeg, lonDeg).elevationDeg;
}

/// Is the satellite still in sunlight? Cylindrical shadow model: everything on
/// the far side of the Earth whose perpendicular distance from the Earth-Sun
/// axis is under one Earth radius is eclipsed. (The penumbra is a few seconds
/// wide at these altitudes — not worth the extra machinery.)
bool isSunlit(Vec3 satEci, Vec3 sunEci) {
  final u = sunEci.unit;
  final projection = satEci.dot(u);
  if (projection > 0) return true; // sunward hemisphere
  final perpendicular =
      math.sqrt(math.max(0.0, satEci.dot(satEci) - projection * projection));
  return perpendicular > earthRadiusKm;
}

/// Estimated apparent visual magnitude, the standard satellite formula:
/// `m = m0 - 15.75 + 2.5*log10(range^2 / illuminatedFraction)`, where `m0` is
/// the object's magnitude at 1000 km fully lit. Only meaningful when a standard
/// magnitude is known for the object — callers pass null for the rest and the UI
/// shows a dash rather than inventing a number.
double? apparentMagnitude({
  required double? standardMagnitude,
  required Vec3 satEci,
  required Vec3 sunEci,
  required Vec3 observerEci,
  required double rangeKm,
}) {
  if (standardMagnitude == null || rangeKm <= 0) return null;
  final toSun = (sunEci - satEci).unit;
  final toObs = (observerEci - satEci).unit;
  final cosPhase = toSun.dot(toObs).clamp(-1.0, 1.0);
  final fraction = (1.0 + cosPhase) / 2.0;
  if (fraction <= 1e-6) return null; // edge-on, effectively unlit
  return standardMagnitude -
      15.75 +
      2.5 * (math.log(rangeKm * rangeKm / fraction) / math.ln10);
}

/// One fully-evaluated instant for one satellite: everything the UI needs.
class SkyFix {
  const SkyFix({
    required this.time,
    required this.look,
    required this.sunlit,
    required this.sunElevationDeg,
    required this.magnitude,
  });

  final DateTime time;
  final LookAngles look;
  final bool sunlit;
  final double sunElevationDeg;
  final double? magnitude;

  /// Naked-eye visible: above the horizon, lit by the Sun, and your own sky is
  /// dark. Missing any one of the three and there is nothing to look at.
  bool get nakedEyeVisible =>
      look.elevationDeg > 0 && sunlit && sunElevationDeg < -6.0;
}

/// Evaluates one satellite at one instant for one observer.
SkyFix? skyFix({
  required Sgp4Satellite sat,
  required DateTime timeUtc,
  required double latDeg,
  required double lonDeg,
  required double altKm,
  double? standardMagnitude,
}) {
  final jd = julianDateOf(timeUtc);
  final state = sat.propagate((jd - sat.tle.epochJd) * 1440.0);
  if (state == null) return null;

  final gmst = gmstRadians(jd);
  final teme = Vec3(state.x, state.y, state.z);
  final ecef = temeToEcef(teme, gmst);
  final site = observerEcef(latDeg, lonDeg, altKm);
  final look = lookAngles(ecef, site, latDeg, lonDeg);

  final sun = sunPositionEci(jd);
  final sunEcef = temeToEcef(sun, gmst);
  final sunEl = lookAngles(sunEcef, site, latDeg, lonDeg).elevationDeg;

  // Magnitude geometry is frame-agnostic as long as everything is consistent;
  // Earth-fixed is convenient because the observer is already there.
  final mag = apparentMagnitude(
    standardMagnitude: standardMagnitude,
    satEci: ecef,
    sunEci: sunEcef,
    observerEci: site,
    rangeKm: look.rangeKm,
  );

  return SkyFix(
    time: timeUtc,
    look: look,
    sunlit: isSunlit(ecef, sunEcef),
    sunElevationDeg: sunEl,
    magnitude: mag,
  );
}
