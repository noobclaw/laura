/// SGP4 — the orbital propagator TLEs are *defined against*. A two-line element
/// set is not a set of osculating orbital elements you can feed to a Kepler
/// solver; it is a set of mean elements that only mean anything when run back
/// through the same model that produced them. Anything else drifts by kilometres
/// within hours, which for a pass predictor means pointing the user at empty sky.
///
/// This is the near-Earth branch only (WGS-72 constants, Hoots & Roehrich /
/// Vallado formulation). Deep-space objects (period >= 225 min) need the SDP4
/// lunar-solar terms, so the catalogue loader refuses to admit them — see
/// [Tle.isDeepSpace]. Everything runs on-device with no allocation beyond the
/// returned state vector.
library;

import 'dart:math' as math;

const double _deg2rad = math.pi / 180.0;
const double _twoPi = math.pi * 2.0;
const double _x2o3 = 2.0 / 3.0;

/// WGS-72 gravity model. TLEs are fitted with these exact values, so using the
/// newer WGS-84 numbers here would be *less* accurate, not more.
class Wgs72 {
  static const double mu = 398600.8; // km^3/s^2
  static const double radiusEarthKm = 6378.135;
  static const double j2 = 0.001082616;
  static const double j3 = -0.00000253881;
  static const double j4 = -0.00000165597;

  /// sqrt(mu) in earth-radii^(3/2) per minute.
  static final double xke =
      60.0 / math.sqrt(radiusEarthKm * radiusEarthKm * radiusEarthKm / mu);
  static const double j3oj2 = j3 / j2;

  /// Converts the propagator's internal velocity unit to km/s.
  static final double vkmPerSec = radiusEarthKm * xke / 60.0;
}

/// A parsed two-line element set.
class Tle {
  Tle({
    required this.name,
    required this.satnum,
    required this.epochJd,
    required this.bstar,
    required this.inclo,
    required this.nodeo,
    required this.ecco,
    required this.argpo,
    required this.mo,
    required this.noKozai,
    required this.line1,
    required this.line2,
  });

  final String name;
  final String satnum;

  /// Julian date (UTC) of the element epoch.
  final double epochJd;
  final double bstar;

  /// Mean elements at epoch — angles in radians, [noKozai] in rad/min.
  final double inclo, nodeo, ecco, argpo, mo, noKozai;

  /// Kept verbatim so an imported set can be re-serialised without loss.
  final String line1, line2;

  /// Orbital period in minutes.
  double get periodMinutes => _twoPi / noKozai;

  /// SGP4's near-Earth branch is only valid below this; above it the lunar-solar
  /// resonance terms of SDP4 are required.
  bool get isDeepSpace => periodMinutes >= 225.0;

  /// How stale the elements are at [now]. Pass predictions degrade roughly a
  /// minute per fortnight for low orbits, so the UI shows this everywhere.
  double ageInDays(DateTime now) =>
      julianDateOf(now) - epochJd;

  /// Parses the classic 3-line (name + 2 element lines) or bare 2-line form.
  /// Returns null when the lines are not a well-formed element set — callers
  /// treat that as "skip this record", never as a crash.
  /// TLE modulo-10 checksum: digits summed, each '-' counts 1, everything
  /// else 0; column 69 holds the result. A line that was OCR'd or hand-typed
  /// with one wrong digit used to parse "successfully" into a silently wrong
  /// orbit — now it is rejected.
  static bool checksumOk(String line) {
    if (line.length < 69) return true; // short lines were never checksummed
    var sum = 0;
    for (var i = 0; i < 68; i++) {
      final c = line.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) sum += c - 0x30;
      if (c == 0x2D) sum += 1;
    }
    final want = line.codeUnitAt(68) - 0x30;
    return sum % 10 == want;
  }

  static Tle? parse(String name, String l1, String l2) {
    try {
      if (l1.length < 63 || l2.length < 63) return null;
      if (!l1.startsWith('1 ') || !l2.startsWith('2 ')) return null;
      if (!checksumOk(l1) || !checksumOk(l2)) return null;

      final satnum = l1.substring(2, 7).trim();
      if (satnum.isEmpty) return null;
      if (l2.substring(2, 7).trim() != satnum) return null;

      final epochYear = int.parse(l1.substring(18, 20).trim());
      final epochDay = double.parse(l1.substring(20, 32).trim());
      final fullYear = epochYear < 57 ? 2000 + epochYear : 1900 + epochYear;
      final epochJd = julianDateOfYearStart(fullYear) + epochDay - 1.0;

      final bstar = _parseImpliedExponent(l1.substring(53, 61));

      final inclo = double.parse(l2.substring(8, 16).trim()) * _deg2rad;
      final nodeo = double.parse(l2.substring(17, 25).trim()) * _deg2rad;
      final ecco = double.parse('0.${l2.substring(26, 33).trim()}');
      final argpo = double.parse(l2.substring(34, 42).trim()) * _deg2rad;
      final mo = double.parse(l2.substring(43, 51).trim()) * _deg2rad;
      final revsPerDay = double.parse(l2.substring(52, 63).trim());

      if (revsPerDay <= 0) return null;
      if (ecco < 0 || ecco >= 1.0) return null;

      return Tle(
        name: name.trim().isEmpty ? satnum : name.trim(),
        satnum: satnum,
        epochJd: epochJd,
        bstar: bstar,
        inclo: inclo,
        nodeo: nodeo,
        ecco: ecco,
        argpo: argpo,
        mo: mo,
        noKozai: revsPerDay * _twoPi / 1440.0,
        line1: l1,
        line2: l2,
      );
    } catch (_) {
      return null;
    }
  }

  /// Pulls every element set out of a blob of text — the exact shape a user gets
  /// from copying a CelesTrak page. Tolerates blank lines, CRLF, and a missing
  /// name line (the satellite number stands in).
  static List<Tle> parseAll(String text) {
    // Text copied out of Notes, a chat app or a browser's reader mode
    // arrives with leading indentation, tabs and NBSPs; a TLE line never
    // legitimately starts with whitespace, so trimming both ends is safe.
    // CelesTrak's 3LE form prefixes the name line with "0 " — drop it.
    final lines = text
        .split(RegExp(r'\r?\n|\r'))
        .map((l) => l.replaceAll(' ', ' ').replaceAll('\t', ' ').trim())
        .where((l) => l.isNotEmpty)
        .map((l) => l.startsWith('0 ') && !l.startsWith('0 0') ? l.substring(2) : l)
        .toList();
    final out = <Tle>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.startsWith('1 ') && i + 1 < lines.length && lines[i + 1].startsWith('2 ')) {
        // Bare 2-line pair; the preceding line (if any) was already consumed.
        final tle = Tle.parse('', line, lines[i + 1]);
        if (tle != null) out.add(tle);
        i += 2;
        continue;
      }
      if (i + 2 < lines.length &&
          lines[i + 1].startsWith('1 ') &&
          lines[i + 2].startsWith('2 ')) {
        final tle = Tle.parse(line, lines[i + 1], lines[i + 2]);
        if (tle != null) out.add(tle);
        i += 3;
        continue;
      }
      i += 1;
    }
    return out;
  }
}

/// TLEs pack small numbers as `12345-3`, meaning 0.12345e-3: the decimal point
/// is implied and the exponent sign is glued on with no `e`.
double _parseImpliedExponent(String field) {
  var t = field.trim();
  if (t.isEmpty) return 0.0;
  var sign = 1.0;
  if (t.startsWith('-')) {
    sign = -1.0;
    t = t.substring(1);
  } else if (t.startsWith('+')) {
    t = t.substring(1);
  }
  if (t.isEmpty) return 0.0;

  var expIdx = -1;
  for (var i = t.length - 1; i > 0; i--) {
    if (t[i] == '+' || t[i] == '-') {
      expIdx = i;
      break;
    }
  }
  final digits = expIdx < 0 ? t : t.substring(0, expIdx);
  final exp = expIdx < 0 ? 0 : int.parse(t.substring(expIdx));
  if (digits.isEmpty) return 0.0;
  final mantissa = double.parse('0.$digits');
  return sign * mantissa * math.pow(10.0, exp);
}

/// Position and velocity in the TEME frame (km, km/s) at one instant.
class StateVector {
  const StateVector(this.x, this.y, this.z, this.vx, this.vy, this.vz);
  final double x, y, z;
  final double vx, vy, vz;

  double get radiusKm => math.sqrt(x * x + y * y + z * z);
  double get speedKmPerSec => math.sqrt(vx * vx + vy * vy + vz * vz);
}

/// A TLE with its SGP4 initialisation pre-computed. Build once per satellite,
/// then call [propagate] as often as the pass search needs — the constructor
/// does all the expensive one-time work.
class Sgp4Satellite {
  Sgp4Satellite(this.tle) {
    _init();
  }

  final Tle tle;

  // Derived at init and constant thereafter.
  late final double _no, _ecco, _inclo, _nodeo, _argpo, _mo, _bstar;
  late final double _cc1, _cc4, _cc5, _t2cof, _omgcof, _xmcof, _nodecf;
  late final double _mdot, _argpdot, _nodedot;
  late final double _con41, _x1mth2, _x7thm1, _xlcof, _aycof, _delmo, _sinmao;
  late final double _eta, _sinio, _cosio;
  late final double _d2, _d3, _d4, _t3cof, _t4cof, _t5cof;
  late final bool _simpleModel;

  /// Set when the elements describe an orbit the near-Earth model cannot
  /// propagate (decayed or deep space). Such satellites are dropped by the
  /// catalogue rather than silently producing nonsense.
  bool get usable => _usable;
  bool _usable = true;

  void _init() {
    _ecco = tle.ecco;
    _inclo = tle.inclo;
    _nodeo = tle.nodeo;
    _argpo = tle.argpo;
    _mo = tle.mo;
    _bstar = tle.bstar;

    const ss = 78.0 / Wgs72.radiusEarthKm + 1.0;
    final qzms2t = math.pow((120.0 - 78.0) / Wgs72.radiusEarthKm, 4.0).toDouble();

    _cosio = math.cos(_inclo);
    _sinio = math.sin(_inclo);
    final cosio2 = _cosio * _cosio;
    final omeosq = 1.0 - _ecco * _ecco;
    final rteosq = math.sqrt(omeosq);

    // Recover the *original* mean motion: the value in the TLE has the Kozai
    // secular J2 correction baked in.
    final ak = math.pow(Wgs72.xke / tle.noKozai, _x2o3).toDouble();
    final d1 = 0.75 * Wgs72.j2 * (3.0 * cosio2 - 1.0) / (rteosq * omeosq);
    var del = d1 / (ak * ak);
    final adel = ak * (1.0 - del * del - del * (1.0 / 3.0 + 134.0 * del * del / 81.0));
    del = d1 / (adel * adel);
    _no = tle.noKozai / (1.0 + del);

    final ao = math.pow(Wgs72.xke / _no, _x2o3).toDouble();
    final po = ao * omeosq;
    final con42 = 1.0 - 5.0 * cosio2;
    _con41 = 3.0 * cosio2 - 1.0;
    final posq = po * po;
    final rp = ao * (1.0 - _ecco);

    if (rp < 1.0 || _no <= 0.0) {
      _usable = false;
    }

    var sfour = ss;
    var qzms24 = qzms2t;
    final perigeeKm = (rp - 1.0) * Wgs72.radiusEarthKm;
    if (perigeeKm < 156.0) {
      sfour = perigeeKm - 78.0;
      if (perigeeKm < 98.0) sfour = 20.0;
      qzms24 = math.pow((120.0 - sfour) / Wgs72.radiusEarthKm, 4.0).toDouble();
      sfour = sfour / Wgs72.radiusEarthKm + 1.0;
    }

    final pinvsq = 1.0 / posq;
    final tsi = 1.0 / (ao - sfour);
    _eta = ao * _ecco * tsi;
    final etasq = _eta * _eta;
    final eeta = _ecco * _eta;
    final psisq = (1.0 - etasq).abs();
    final coef = qzms24 * math.pow(tsi, 4.0).toDouble();
    final coef1 = coef / math.pow(psisq, 3.5).toDouble();

    final cc2 = coef1 *
        _no *
        (ao * (1.0 + 1.5 * etasq + eeta * (4.0 + etasq)) +
            0.375 *
                Wgs72.j2 *
                tsi /
                psisq *
                _con41 *
                (8.0 + 3.0 * etasq * (8.0 + etasq)));
    _cc1 = _bstar * cc2;
    var cc3 = 0.0;
    if (_ecco > 1.0e-4) {
      cc3 = -2.0 * coef * tsi * Wgs72.j3oj2 * _no * _sinio / _ecco;
    }
    _x1mth2 = 1.0 - cosio2;
    _cc4 = 2.0 *
        _no *
        coef1 *
        ao *
        omeosq *
        (_eta * (2.0 + 0.5 * etasq) +
            _ecco * (0.5 + 2.0 * etasq) -
            Wgs72.j2 *
                tsi /
                (ao * psisq) *
                (-3.0 *
                        _con41 *
                        (1.0 - 2.0 * eeta + etasq * (1.5 - 0.5 * eeta)) +
                    0.75 *
                        _x1mth2 *
                        (2.0 * etasq - eeta * (1.0 + etasq)) *
                        math.cos(2.0 * _argpo)));
    _cc5 = 2.0 *
        coef1 *
        ao *
        omeosq *
        (1.0 + 2.75 * (etasq + eeta) + eeta * etasq);

    final cosio4 = cosio2 * cosio2;
    final temp1 = 1.5 * Wgs72.j2 * pinvsq * _no;
    final temp2 = 0.5 * temp1 * Wgs72.j2 * pinvsq;
    final temp3 = -0.46875 * Wgs72.j4 * pinvsq * pinvsq * _no;

    _mdot = _no +
        0.5 * temp1 * rteosq * _con41 +
        0.0625 * temp2 * rteosq * (13.0 - 78.0 * cosio2 + 137.0 * cosio4);
    _argpdot = -0.5 * temp1 * con42 +
        0.0625 * temp2 * (7.0 - 114.0 * cosio2 + 395.0 * cosio4) +
        temp3 * (3.0 - 36.0 * cosio2 + 49.0 * cosio4);
    final xhdot1 = -temp1 * _cosio;
    _nodedot = xhdot1 +
        (0.5 * temp2 * (4.0 - 19.0 * cosio2) +
                2.0 * temp3 * (3.0 - 7.0 * cosio2)) *
            _cosio;

    _omgcof = _bstar * cc3 * math.cos(_argpo);
    _xmcof = _ecco > 1.0e-4 ? -_x2o3 * coef * _bstar / eeta : 0.0;
    _nodecf = 3.5 * omeosq * xhdot1 * _cc1;
    _t2cof = 1.5 * _cc1;

    // Guard the singularity at exactly polar-retrograde inclination.
    final cosioPlus1 = _cosio + 1.0;
    _xlcof = cosioPlus1.abs() > 1.5e-12
        ? -0.25 * Wgs72.j3oj2 * _sinio * (3.0 + 5.0 * _cosio) / cosioPlus1
        : -0.25 * Wgs72.j3oj2 * _sinio * (3.0 + 5.0 * _cosio) / 1.5e-12;
    _aycof = -0.5 * Wgs72.j3oj2 * _sinio;
    _delmo = math.pow(1.0 + _eta * math.cos(_mo), 3.0).toDouble();
    _sinmao = math.sin(_mo);
    _x7thm1 = 7.0 * cosio2 - 1.0;

    // Very low orbits use the truncated ("simplified") drag model.
    _simpleModel = (ao * (1.0 - _ecco)) < (220.0 / Wgs72.radiusEarthKm + 1.0);

    if (_simpleModel) {
      _d2 = 0.0;
      _d3 = 0.0;
      _d4 = 0.0;
      _t3cof = 0.0;
      _t4cof = 0.0;
      _t5cof = 0.0;
    } else {
      final cc1sq = _cc1 * _cc1;
      _d2 = 4.0 * ao * tsi * cc1sq;
      final temp = _d2 * tsi * _cc1 / 3.0;
      _d3 = (17.0 * ao + sfour) * temp;
      _d4 = 0.5 * temp * ao * tsi * (221.0 * ao + 31.0 * sfour) * _cc1;
      _t3cof = _d2 + 2.0 * cc1sq;
      _t4cof = 0.25 * (3.0 * _d3 + _cc1 * (12.0 * _d2 + 10.0 * cc1sq));
      _t5cof = 0.2 *
          (3.0 * _d4 +
              12.0 * _cc1 * _d3 +
              6.0 * _d2 * _d2 +
              15.0 * cc1sq * (2.0 * _d2 + cc1sq));
    }
  }

  /// Propagates to [tsince] minutes past the element epoch. Returns null when
  /// the model breaks down (decayed orbit) rather than emitting a bogus vector.
  StateVector? propagate(double tsince) {
    if (!_usable) return null;

    final xmdf = _mo + _mdot * tsince;
    final argpdf = _argpo + _argpdot * tsince;
    final nodedf = _nodeo + _nodedot * tsince;
    var argpm = argpdf;
    var mm = xmdf;
    final t2 = tsince * tsince;
    var nodem = nodedf + _nodecf * t2;
    var tempa = 1.0 - _cc1 * tsince;
    var tempe = _bstar * _cc4 * tsince;
    var templ = _t2cof * t2;

    if (!_simpleModel) {
      final delomg = _omgcof * tsince;
      final delm =
          _xmcof * (math.pow(1.0 + _eta * math.cos(xmdf), 3.0).toDouble() - _delmo);
      final temp = delomg + delm;
      mm = xmdf + temp;
      argpm = argpdf - temp;
      final t3 = t2 * tsince;
      final t4 = t3 * tsince;
      tempa = tempa - _d2 * t2 - _d3 * t3 - _d4 * t4;
      tempe = tempe + _bstar * _cc5 * (math.sin(mm) - _sinmao);
      templ = templ + _t3cof * t3 + t4 * (_t4cof + tsince * _t5cof);
    }

    var nm = _no;
    var em = _ecco;

    final am = math.pow(Wgs72.xke / nm, _x2o3).toDouble() * tempa * tempa;
    if (am <= 0.0) return null;
    nm = Wgs72.xke / math.pow(am, 1.5).toDouble();
    em -= tempe;
    // A decayed / over-corrected orbit: refuse rather than propagate garbage.
    if (em >= 1.0 || em < -0.001) return null;
    if (em < 1.0e-6) em = 1.0e-6;

    mm += _no * templ;
    var xlm = mm + argpm + nodem;

    nodem = nodem % _twoPi;
    argpm = argpm % _twoPi;
    xlm = xlm % _twoPi;
    mm = (xlm - argpm - nodem) % _twoPi;

    // Long-period periodics.
    final axnl = em * math.cos(argpm);
    var temp = 1.0 / (am * (1.0 - em * em));
    final aynl = em * math.sin(argpm) + temp * _aycof;
    final xl = mm + argpm + nodem + temp * _xlcof * axnl;

    // Kepler's equation, Newton-Raphson with the classic step clamp.
    final u = (xl - nodem) % _twoPi;
    var eo1 = u;
    var tem5 = 9999.9;
    var ktr = 1;
    var sineo1 = 0.0, coseo1 = 0.0;
    while (tem5.abs() >= 1.0e-12 && ktr <= 10) {
      sineo1 = math.sin(eo1);
      coseo1 = math.cos(eo1);
      tem5 = 1.0 - coseo1 * axnl - sineo1 * aynl;
      tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / tem5;
      if (tem5.abs() >= 0.95) tem5 = tem5 > 0.0 ? 0.95 : -0.95;
      eo1 += tem5;
      ktr++;
    }

    final ecose = axnl * coseo1 + aynl * sineo1;
    final esine = axnl * sineo1 - aynl * coseo1;
    final el2 = axnl * axnl + aynl * aynl;
    final pl = am * (1.0 - el2);
    if (pl < 0.0) return null;

    final rl = am * (1.0 - ecose);
    final rdotl = math.sqrt(am) * esine / rl;
    final rvdotl = math.sqrt(pl) / rl;
    final betal = math.sqrt(1.0 - el2);
    temp = esine / (1.0 + betal);
    final sinu = am / rl * (sineo1 - aynl - axnl * temp);
    final cosu = am / rl * (coseo1 - axnl + aynl * temp);
    var su = math.atan2(sinu, cosu);
    final sin2u = (cosu + cosu) * sinu;
    final cos2u = 1.0 - 2.0 * sinu * sinu;
    temp = 1.0 / pl;
    final temp1 = 0.5 * Wgs72.j2 * temp;
    final temp2 = temp1 * temp;

    // Short-period periodics.
    final mrt = rl * (1.0 - 1.5 * temp2 * betal * _con41) +
        0.5 * temp1 * _x1mth2 * cos2u;
    su -= 0.25 * temp2 * _x7thm1 * sin2u;
    final xnode = nodem + 1.5 * temp2 * _cosio * sin2u;
    final xinc = _inclo + 1.5 * temp2 * _cosio * _sinio * cos2u;
    final mvt = rdotl - nm * temp1 * _x1mth2 * sin2u / Wgs72.xke;
    final rvdot =
        rvdotl + nm * temp1 * (_x1mth2 * cos2u + 1.5 * _con41) / Wgs72.xke;

    if (mrt < 1.0) return null; // decayed below the surface

    // Orientation vectors.
    final sinsu = math.sin(su);
    final cossu = math.cos(su);
    final snod = math.sin(xnode);
    final cnod = math.cos(xnode);
    final sini = math.sin(xinc);
    final cosi = math.cos(xinc);
    final xmx = -snod * cosi;
    final xmy = cnod * cosi;
    final ux = xmx * sinsu + cnod * cossu;
    final uy = xmy * sinsu + snod * cossu;
    final uz = sini * sinsu;
    final vx = xmx * cossu - cnod * sinsu;
    final vy = xmy * cossu - snod * sinsu;
    final vz = sini * cossu;

    return StateVector(
      mrt * ux * Wgs72.radiusEarthKm,
      mrt * uy * Wgs72.radiusEarthKm,
      mrt * uz * Wgs72.radiusEarthKm,
      (mvt * ux + rvdot * vx) * Wgs72.vkmPerSec,
      (mvt * uy + rvdot * vy) * Wgs72.vkmPerSec,
      (mvt * uz + rvdot * vz) * Wgs72.vkmPerSec,
    );
  }

  /// Convenience: propagate to a wall-clock instant.
  StateVector? at(DateTime utc) =>
      propagate((julianDateOf(utc) - tle.epochJd) * 1440.0);
}

/// Julian date of `year`-01-01 00:00 UTC.
double julianDateOfYearStart(int year) =>
    367.0 * year -
    ((7 * (year + ((1 + 9) ~/ 12))) ~/ 4) +
    (275 * 1) ~/ 9 +
    1 +
    1721013.5;

/// Inverse of [julianDateOf]. The pass search runs entirely in Julian days
/// (a plain double is far cheaper to step than a DateTime) and converts back
/// only for the handful of instants that reach the UI.
DateTime dateTimeFromJulian(double jd) => DateTime.fromMillisecondsSinceEpoch(
      ((jd - 2440587.5) * 86400000.0).round(),
      isUtc: true,
    );

/// Julian date (UTC) of an instant. Leap seconds are ignored — UT1-UTC stays
/// under a second, which is far below the accuracy a TLE can support anyway.
double julianDateOf(DateTime t) {
  final u = t.toUtc();
  final seconds = u.second + u.millisecond / 1000.0 + u.microsecond / 1000000.0;
  return 367.0 * u.year -
      ((7 * (u.year + ((u.month + 9) ~/ 12))) ~/ 4) +
      (275 * u.month) ~/ 9 +
      u.day +
      1721013.5 +
      ((seconds / 60.0 + u.minute) / 60.0 + u.hour) / 24.0;
}
