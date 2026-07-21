// Pure-Dart astronomical almanac for the Sun and Moon.
//
// Everything here is deterministic device-side math — no network, no plugins.
// Positions use a compact port of Paul Schlyter's low-precision ephemeris
// (sun ~1', moon ~2' after perturbations), which is far more than photography
// planning needs. Event times (sunrise, golden hour, …) are found by sampling
// the Sun's altitude across the local day and interpolating threshold
// crossings — one altitude function drives every twilight boundary and yields
// the Sun's compass azimuth at each event for free.

import 'dart:math' as math;

const double _deg2rad = math.pi / 180.0;
const double _rad2deg = 180.0 / math.pi;

double _sinD(double deg) => math.sin(deg * _deg2rad);
double _cosD(double deg) => math.cos(deg * _deg2rad);
double _asinD(double x) => math.asin(x.clamp(-1.0, 1.0)) * _rad2deg;
double _atan2D(double y, double x) => math.atan2(y, x) * _rad2deg;

/// Normalize an angle in degrees into [0, 360).
double normDeg(double d) {
  var r = d % 360.0;
  if (r < 0) r += 360.0;
  return r;
}

/// Schlyter's day number: days since 2000-01-00 00:00 UT (i.e. 1999-12-31 0h),
/// as a real number including the fractional day. Input must be UTC.
double dayNumber(DateTime utc) {
  final d = utc.toUtc();
  final y = d.year, m = d.month, day = d.day;
  // Integer-truncating day count (Schlyter), then add fractional UT.
  final dn = 367 * y -
      (7 * (y + ((m + 9) ~/ 12))) ~/ 4 +
      (275 * m) ~/ 9 +
      day -
      730530;
  final ut = d.hour + d.minute / 60.0 + d.second / 3600.0 + d.millisecond / 3.6e6;
  return dn + ut / 24.0;
}

/// Obliquity of the ecliptic for day number [d].
double _obliquity(double d) => 23.4393 - 3.563e-7 * d;

/// A position in the equatorial frame plus the observer-independent ecliptic
/// longitude (used for the Moon phase / elongation).
class _Equatorial {
  final double ra; // right ascension, degrees
  final double dec; // declination, degrees
  final double eclipticLon; // apparent ecliptic longitude, degrees
  const _Equatorial(this.ra, this.dec, this.eclipticLon);
}

/// Horizontal coordinates as seen from an observer.
class SkyPosition {
  /// Compass azimuth in degrees, measured clockwise from true North.
  final double azimuth;

  /// Altitude above the horizon in degrees (negative = below).
  final double altitude;
  const SkyPosition(this.azimuth, this.altitude);
}

/// Local sidereal time in degrees at UT day number [d] for east-positive
/// [lonDeg].
double _localSiderealTime(double d, double lonDeg) {
  // Sun's mean longitude gives the sidereal time reference (Schlyter).
  final w = 282.9404 + 4.70935e-5 * d;
  final m = 356.0470 + 0.9856002585 * d;
  final ls = normDeg(w + m); // Sun's mean longitude
  final ut = (d - d.floorToDouble()) * 24.0; // fractional day -> hours UT
  final gmst0 = ls / 15.0 + 12.0; // hours
  final lst = gmst0 + ut + lonDeg / 15.0; // hours
  return normDeg(lst * 15.0);
}

/// Convert an equatorial position to horizontal coords for the observer.
SkyPosition _toHorizontal(_Equatorial eq, double d, double latDeg, double lonDeg) {
  final lst = _localSiderealTime(d, lonDeg);
  final ha = normDeg(lst - eq.ra); // hour angle, degrees
  final sinAlt = _sinD(latDeg) * _sinD(eq.dec) +
      _cosD(latDeg) * _cosD(eq.dec) * _cosD(ha);
  final alt = _asinD(sinAlt);
  // Azimuth measured from North, clockwise.
  final y = -_cosD(eq.dec) * _sinD(ha);
  final x = _sinD(eq.dec) * _cosD(latDeg) - _cosD(eq.dec) * _cosD(ha) * _sinD(latDeg);
  final az = normDeg(_atan2D(y, x));
  return SkyPosition(az, alt);
}

/// Sun equatorial position for day number [d].
_Equatorial _sunEquatorial(double d) {
  final w = 282.9404 + 4.70935e-5 * d;
  final e = 0.016709 - 1.151e-9 * d;
  final m = normDeg(356.0470 + 0.9856002585 * d);
  final oblecl = _obliquity(d);

  // Eccentric anomaly (deg), one Kepler iteration is plenty for the Sun.
  final eAnom = m + _rad2deg * e * _sinD(m) * (1 + e * _cosD(m));
  final x = _cosD(eAnom) - e;
  final y = _sinD(eAnom) * math.sqrt(1 - e * e);
  final r = math.sqrt(x * x + y * y);
  final v = _atan2D(y, x);
  final lon = normDeg(v + w); // true ecliptic longitude

  final xs = r * _cosD(lon);
  final ys = r * _sinD(lon);
  // Rotate ecliptic -> equatorial.
  final xe = xs;
  final ye = ys * _cosD(oblecl);
  final ze = ys * _sinD(oblecl);
  final ra = normDeg(_atan2D(ye, xe));
  final dec = _atan2D(ze, math.sqrt(xe * xe + ye * ye));
  return _Equatorial(ra, dec, lon);
}

/// Moon equatorial position for day number [d], with Schlyter's main
/// perturbation terms applied (brings accuracy to a couple of arc-minutes).
_Equatorial _moonEquatorial(double d) {
  final nNode = 125.1228 - 0.0529538083 * d;
  const incl = 5.1454;
  final w = 318.0634 + 0.1643573223 * d;
  const a = 60.2666; // Earth radii
  const ecc = 0.054900;
  final m = normDeg(115.3654 + 13.0649929509 * d);
  final oblecl = _obliquity(d);

  // Eccentric anomaly, two iterations for the Moon's larger eccentricity.
  var eAnom = m + _rad2deg * ecc * _sinD(m) * (1 + ecc * _cosD(m));
  eAnom = eAnom -
      (eAnom - _rad2deg * ecc * _sinD(eAnom) - m) / (1 - ecc * _cosD(eAnom));

  final x = a * (_cosD(eAnom) - ecc);
  final y = a * math.sqrt(1 - ecc * ecc) * _sinD(eAnom);
  final r = math.sqrt(x * x + y * y);
  final v = _atan2D(y, x);

  // Ecliptic rectangular coordinates.
  var xeclip = r *
      (_cosD(nNode) * _cosD(v + w) - _sinD(nNode) * _sinD(v + w) * _cosD(incl));
  var yeclip = r *
      (_sinD(nNode) * _cosD(v + w) + _cosD(nNode) * _sinD(v + w) * _cosD(incl));
  var zeclip = r * _sinD(v + w) * _sinD(incl);

  var lon = normDeg(_atan2D(yeclip, xeclip));
  var lat = _atan2D(zeclip, math.sqrt(xeclip * xeclip + yeclip * yeclip));

  // --- Perturbations (Schlyter). Need the Sun's mean anomaly/longitude. ---
  final ws = 282.9404 + 4.70935e-5 * d;
  final ms = normDeg(356.0470 + 0.9856002585 * d); // Sun mean anomaly
  final ls = normDeg(ws + ms); // Sun mean longitude
  final lm = normDeg(nNode + w + m); // Moon mean longitude
  final dElong = normDeg(lm - ls); // mean elongation
  final f = normDeg(lm - nNode); // argument of latitude

  lon += -1.274 * _sinD(m - 2 * dElong); // Evection
  lon += 0.658 * _sinD(2 * dElong); // Variation
  lon += -0.186 * _sinD(ms); // Yearly equation
  lon += -0.059 * _sinD(2 * m - 2 * dElong);
  lon += -0.057 * _sinD(m - 2 * dElong + ms);
  lon += 0.053 * _sinD(m + 2 * dElong);
  lon += 0.046 * _sinD(2 * dElong - ms);
  lon += 0.041 * _sinD(m - ms);
  lon += -0.035 * _sinD(dElong); // Parallactic equation
  lon += -0.031 * _sinD(m + ms);
  lon += -0.015 * _sinD(2 * f - 2 * dElong);
  lon += 0.011 * _sinD(m - 4 * dElong);

  lat += -0.173 * _sinD(f - 2 * dElong);
  lat += -0.055 * _sinD(m - f - 2 * dElong);
  lat += -0.046 * _sinD(m + f - 2 * dElong);
  lat += 0.033 * _sinD(f + 2 * dElong);
  lat += 0.017 * _sinD(2 * m + f);

  lon = normDeg(lon);

  // Ecliptic (lon/lat) -> equatorial.
  final xh = _cosD(lon) * _cosD(lat);
  final yh = _sinD(lon) * _cosD(lat);
  final zh = _sinD(lat);
  final xe = xh;
  final ye = yh * _cosD(oblecl) - zh * _sinD(oblecl);
  final ze = yh * _sinD(oblecl) + zh * _cosD(oblecl);
  final ra = normDeg(_atan2D(ye, xe));
  final dec = _atan2D(ze, math.sqrt(xe * xe + ye * ye));
  return _Equatorial(ra, dec, lon);
}

/// Sun horizontal position at [utc] for the observer.
SkyPosition sunPosition(DateTime utc, double lat, double lon) {
  final d = dayNumber(utc);
  return _toHorizontal(_sunEquatorial(d), d, lat, lon);
}

/// Moon horizontal position at [utc] for the observer.
SkyPosition moonPosition(DateTime utc, double lat, double lon) {
  final d = dayNumber(utc);
  return _toHorizontal(_moonEquatorial(d), d, lat, lon);
}

/// Illuminated fraction (0..1) and named phase of the Moon at [utc].
class MoonPhase {
  final double illumination; // 0 = new, 1 = full
  final double elongation; // Moon-Sun ecliptic longitude difference, [0,360)
  final String name;
  final bool waxing;
  const MoonPhase({
    required this.illumination,
    required this.elongation,
    required this.name,
    required this.waxing,
  });
}

MoonPhase moonPhase(DateTime utc) {
  final d = dayNumber(utc);
  final sun = _sunEquatorial(d);
  final moon = _moonEquatorial(d);
  final elong = normDeg(moon.eclipticLon - sun.eclipticLon);
  final illum = (1 - _cosD(elong)) / 2.0;
  final waxing = elong < 180.0;
  String name;
  if (elong < 11.25 || elong >= 348.75) {
    name = 'New Moon';
  } else if (elong < 78.75) {
    name = 'Waxing Crescent';
  } else if (elong < 101.25) {
    name = 'First Quarter';
  } else if (elong < 168.75) {
    name = 'Waxing Gibbous';
  } else if (elong < 191.25) {
    name = 'Full Moon';
  } else if (elong < 258.75) {
    name = 'Waning Gibbous';
  } else if (elong < 281.25) {
    name = 'Last Quarter';
  } else {
    name = 'Waning Crescent';
  }
  return MoonPhase(illumination: illum, elongation: elong, name: name, waxing: waxing);
}

/// A single dawn/dusk boundary: the instant plus the body's compass azimuth.
class LightMoment {
  final DateTime? time; // local time; null if the Sun never reaches the angle
  final double? azimuth; // compass azimuth at that instant
  const LightMoment(this.time, this.azimuth);

  bool get exists => time != null;
}

/// Altitude thresholds (degrees) that delimit the photographic light windows.
class SunAltitudes {
  static const double sunrise = -0.833; // refraction + solar radius
  static const double civil = -6.0; // civil twilight / blue-hour outer edge
  static const double goldenLow = -4.0; // blue/golden boundary
  static const double goldenHigh = 6.0; // golden hour upper edge
}

/// The full day's Sun schedule for one location, in local time.
class DayLight {
  final DateTime date; // local calendar day (date-only)
  final double lat;
  final double lon;

  final LightMoment dawnCivil; // first light, blue hour begins (-6 rising)
  final LightMoment goldenStartAm; // -4 rising
  final LightMoment sunrise; // -0.833 rising
  final LightMoment goldenEndAm; // +6 rising
  final DateTime? solarNoon;
  final double? noonAltitude; // Sun's peak altitude of the day
  final LightMoment goldenStartPm; // +6 falling
  final LightMoment sunset; // -0.833 falling
  final LightMoment goldenEndPm; // -4 falling, blue hour begins
  final LightMoment duskCivil; // last light (-6 falling)
  final bool polarDay; // Sun never sets below the sunrise angle
  final bool polarNight; // Sun never rises above the sunrise angle

  const DayLight({
    required this.date,
    required this.lat,
    required this.lon,
    required this.dawnCivil,
    required this.goldenStartAm,
    required this.sunrise,
    required this.goldenEndAm,
    required this.solarNoon,
    required this.noonAltitude,
    required this.goldenStartPm,
    required this.sunset,
    required this.goldenEndPm,
    required this.duskCivil,
    required this.polarDay,
    required this.polarNight,
  });

  /// Length of daylight (sunrise to sunset), or null if there is no
  /// ordinary sunrise/sunset pair on this day.
  Duration? get daylight {
    final r = sunrise.time, s = sunset.time;
    if (r == null || s == null) return null;
    return s.difference(r);
  }
}

/// Compute the Sun schedule for [localDate] at ([lat], [lon]).
///
/// Samples the Sun's altitude minute-by-minute across the local calendar day
/// and interpolates threshold crossings. Times come back in the device's local
/// timezone (correct for the current-location case; for a far manual location
/// they are still the device timezone — the UI notes this).
DayLight computeDayLight(DateTime localDate, double lat, double lon) {
  final dayStart = DateTime(localDate.year, localDate.month, localDate.day);
  const stepMinutes = 1;
  const samples = 24 * 60 ~/ stepMinutes; // 1440

  final times = <DateTime>[];
  final alts = <double>[];
  final azis = <double>[];
  for (var i = 0; i <= samples; i++) {
    final t = dayStart.add(Duration(minutes: i * stepMinutes));
    final p = sunPosition(t.toUtc(), lat, lon);
    times.add(t);
    alts.add(p.altitude);
    azis.add(p.azimuth);
  }

  // Peak altitude / solar noon.
  var maxIdx = 0;
  for (var i = 1; i < alts.length; i++) {
    if (alts[i] > alts[maxIdx]) maxIdx = i;
  }
  final noonAltitude = alts[maxIdx];
  final solarNoon = times[maxIdx];

  // Interpolate the local time + azimuth where altitude crosses [threshold]
  // in the requested direction, searching either before (morning) or after
  // (evening) solar noon.
  LightMoment cross(double threshold, {required bool rising}) {
    if (rising) {
      for (var i = 1; i <= maxIdx; i++) {
        if (alts[i - 1] < threshold && alts[i] >= threshold) {
          return _interp(times, alts, azis, i, threshold);
        }
      }
    } else {
      for (var i = maxIdx + 1; i < alts.length; i++) {
        if (alts[i - 1] >= threshold && alts[i] < threshold) {
          return _interp(times, alts, azis, i, threshold);
        }
      }
    }
    return const LightMoment(null, null);
  }

  final minAlt = alts.reduce(math.min);
  final polarDay = minAlt > SunAltitudes.sunrise;
  final polarNight = noonAltitude < SunAltitudes.sunrise;

  return DayLight(
    date: dayStart,
    lat: lat,
    lon: lon,
    dawnCivil: cross(SunAltitudes.civil, rising: true),
    goldenStartAm: cross(SunAltitudes.goldenLow, rising: true),
    sunrise: cross(SunAltitudes.sunrise, rising: true),
    goldenEndAm: cross(SunAltitudes.goldenHigh, rising: true),
    solarNoon: solarNoon,
    noonAltitude: noonAltitude,
    goldenStartPm: cross(SunAltitudes.goldenHigh, rising: false),
    sunset: cross(SunAltitudes.sunrise, rising: false),
    goldenEndPm: cross(SunAltitudes.goldenLow, rising: false),
    duskCivil: cross(SunAltitudes.civil, rising: false),
    polarDay: polarDay,
    polarNight: polarNight,
  );
}

LightMoment _interp(List<DateTime> times, List<double> alts, List<double> azis,
    int i, double threshold) {
  final a0 = alts[i - 1], a1 = alts[i];
  final frac = (threshold - a0) / (a1 - a0);
  final t0 = times[i - 1].millisecondsSinceEpoch;
  final t1 = times[i].millisecondsSinceEpoch;
  final tMs = (t0 + (t1 - t0) * frac).round();
  // Azimuth can wrap 360->0 between samples; interpolate on the short arc.
  var z0 = azis[i - 1], z1 = azis[i];
  var dz = z1 - z0;
  if (dz > 180) dz -= 360;
  if (dz < -180) dz += 360;
  final az = normDeg(z0 + dz * frac);
  return LightMoment(DateTime.fromMillisecondsSinceEpoch(tMs), az);
}

/// Moonrise / moonset for [localDate] at ([lat], [lon]) by the same sampling
/// approach (the Moon's own motion is included since its position is recomputed
/// each step). Returns local times; either may be null on days with no crossing.
class MoonTimes {
  final DateTime? rise;
  final DateTime? set;
  const MoonTimes(this.rise, this.set);
}

MoonTimes computeMoonTimes(DateTime localDate, double lat, double lon) {
  final dayStart = DateTime(localDate.year, localDate.month, localDate.day);
  const stepMinutes = 5;
  const samples = 24 * 60 ~/ stepMinutes;
  const moonRiseAlt = 0.125; // approx horizon incl. refraction + parallax net

  DateTime? rise;
  DateTime? set;
  double? prevAlt;
  DateTime? prevTime;
  for (var i = 0; i <= samples; i++) {
    final t = dayStart.add(Duration(minutes: i * stepMinutes));
    final alt = moonPosition(t.toUtc(), lat, lon).altitude;
    if (prevAlt != null && prevTime != null) {
      if (prevAlt < moonRiseAlt && alt >= moonRiseAlt && rise == null) {
        rise = _lerpTime(prevTime, t, prevAlt, alt, moonRiseAlt);
      }
      if (prevAlt >= moonRiseAlt && alt < moonRiseAlt && set == null) {
        set = _lerpTime(prevTime, t, prevAlt, alt, moonRiseAlt);
      }
    }
    prevAlt = alt;
    prevTime = t;
  }
  return MoonTimes(rise, set);
}

DateTime _lerpTime(DateTime t0, DateTime t1, double a0, double a1, double thr) {
  final frac = (thr - a0) / (a1 - a0);
  final ms = t0.millisecondsSinceEpoch +
      ((t1.millisecondsSinceEpoch - t0.millisecondsSinceEpoch) * frac).round();
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

/// Map a compass azimuth to a 16-point rose label (e.g. "NE", "SSW").
String compassLabel(double azimuth) {
  const points = [
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
  ];
  final idx = ((normDeg(azimuth) + 11.25) / 22.5).floor() % 16;
  return points[idx];
}
