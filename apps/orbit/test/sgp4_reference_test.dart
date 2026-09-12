import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/tool/astro.dart';
import 'package:orbit/tool/sgp4.dart';

/// Reference-fidelity tests. Expected TEME position (km) and velocity (km/s)
/// vectors are copied verbatim from the official SGP4 verification output
/// `tcppver.out` shipped with brandon-rhodes/python-sgp4 (MIT), which is the
/// authoritative port of Vallado's C++ SGP4. `tsince` is minutes past the
/// element epoch, matching [Sgp4Satellite.propagate].
///
/// python-sgp4 — Copyright (c) 2012–2024 Brandon Rhodes, MIT License. No code
/// was copied; only the published verification numbers are reproduced here.
///
/// Tolerance: a correct double-precision propagator reproduces these vectors to
/// well under a metre. We assert 1 metre (1e-3 km) on position and 1e-6 km/s on
/// velocity — three-plus orders tighter than the ~0.1 km the SGP4 standard
/// treats as "matching", so a single mistranscribed coefficient cannot pass.
const double _posTolKm = 1e-3;
const double _velTolKmps = 1e-6;

class _Expect {
  const _Expect(this.t, this.r, this.v);
  final double t; // minutes since epoch
  final List<double> r; // x,y,z km
  final List<double> v; // vx,vy,vz km/s
}

void _checkSat(String name, String l1, String l2, List<_Expect> cases) {
  final tle = Tle.parse(name, l1, l2);
  expect(tle, isNotNull, reason: '$name TLE failed to parse');
  final sat = Sgp4Satellite(tle!);
  expect(sat.usable, isTrue, reason: '$name marked unusable');
  for (final c in cases) {
    final s = sat.propagate(c.t);
    expect(s, isNotNull, reason: '$name propagate(${c.t}) returned null');
    expect(s!.x, closeTo(c.r[0], _posTolKm), reason: '$name t=${c.t} x');
    expect(s.y, closeTo(c.r[1], _posTolKm), reason: '$name t=${c.t} y');
    expect(s.z, closeTo(c.r[2], _posTolKm), reason: '$name t=${c.t} z');
    expect(s.vx, closeTo(c.v[0], _velTolKmps), reason: '$name t=${c.t} vx');
    expect(s.vy, closeTo(c.v[1], _velTolKmps), reason: '$name t=${c.t} vy');
    expect(s.vz, closeTo(c.v[2], _velTolKmps), reason: '$name t=${c.t} vz');
  }
}

void main() {
  group('SGP4-VER.tle reference vectors (from python-sgp4 tcppver.out)', () {
    test('sat 88888 — near-Earth normal drag case', () {
      _checkSat(
        'TEST 88888',
        '1 88888U          80275.98708465  .00073094  13844-3  66816-4 0    87',
        '2 88888  72.8435 115.9689 0086731  52.6988 110.5714 16.05824518  1058',
        const [
          _Expect(0.0, [2328.96975262, -5995.22051338, 1719.97297192],
              [2.912073281, -0.983417956, -7.090816210]),
          _Expect(120.0, [1020.69234558, 2286.56260634, -6191.55565927],
              [-3.746543902, 6.467532721, 1.827985678]),
          _Expect(360.0, [2456.10706533, -6071.93855503, 1222.89768554],
              [2.679390040, -0.448290811, -7.228792155]),
          _Expect(720.0, [2567.56229695, -6112.50383922, 713.96374435],
              [2.440245751, 0.098109002, -7.319959258]),
          _Expect(1440.0, [2742.55398832, -6079.67009123, -326.39012649],
              [1.948497651, 1.211072678, -7.356193131]),
        ],
      );
    });

    test('sat 00005 — high-eccentricity (e=0.186) near-Earth case', () {
      _checkSat(
        'VANGUARD 1',
        '1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753',
        '2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667',
        const [
          _Expect(0.0, [7022.46529266, -1400.08296755, 0.03995155],
              [1.893841015, 6.405893759, 4.534807250]),
          _Expect(360.0, [-7154.03120202, -3783.17682504, -3536.19412294],
              [4.741887409, -4.151817765, -2.093935425]),
          _Expect(720.0, [-7134.59340119, 6531.68641334, 3260.27186483],
              [-4.113793027, -2.911922039, -2.557327851]),
          _Expect(1080.0, [5568.53901181, 4492.06992591, 3863.87641983],
              [-4.209106476, 5.159719888, 2.744852980]),
          _Expect(1440.0, [-938.55923943, -6268.18748831, -4294.02924751],
              [7.536105209, -0.427127707, 0.989878080]),
        ],
      );
    });
  });

  group('ISS pass geometry sanity (real TLE + ground station)', () {
    // A genuine ISS element set; epoch 2026-08-02 12:09 UTC.
    final iss = Tle.parse(
      'ISS (ZARYA)',
      '1 25544U 98067A   26214.50635181  .00006342  00000+0  12183-3 0  9996',
      '2 25544  51.6315  70.8679 0007172   4.7554 355.3502 15.49313226578933',
    )!;

    test('look angles stay physical over a full day and a real pass appears',
        () {
      final sat = Sgp4Satellite(iss);
      // Observer: London (within the ISS 51.6-deg inclination band, so passes
      // must occur).
      const lat = 51.5074, lon = -0.1278, alt = 0.03;
      final epoch = dateTimeFromJulian(iss.epochJd);

      var maxEl = -90.0;
      var sawAbove = false;
      // Step every 30 s for 24 h.
      for (var m = 0; m <= 24 * 60 * 2; m++) {
        final t = epoch.add(Duration(seconds: 30 * m));
        final jd = julianDateOf(t);
        final st = sat.propagate((jd - iss.epochJd) * 1440.0);
        expect(st, isNotNull);
        final gmst = gmstRadians(jd);
        final ecef = temeToEcef(Vec3(st!.x, st.y, st.z), gmst);
        final site = observerEcef(lat, lon, alt);
        final look = lookAngles(ecef, site, lat, lon);

        // Azimuth must be a valid compass bearing.
        expect(look.azimuthDeg, inInclusiveRange(0.0, 360.0));
        // Elevation is a valid angle above/below the horizon.
        expect(look.elevationDeg, inInclusiveRange(-90.0, 90.0));
        // Slant range never drops below the ISS altitude floor (~400 km
        // straight up) and never exceeds Earth diameter + altitude.
        expect(look.rangeKm, inInclusiveRange(390.0, 13500.0));
        // When the satellite is actually up, it is within line-of-sight range.
        if (look.elevationDeg > 0) {
          sawAbove = true;
          expect(look.rangeKm, lessThan(2600.0),
              reason: 'above-horizon slant range too large');
        }
        maxEl = math.max(maxEl, look.elevationDeg);
      }

      // Over a whole day London must get at least one ISS pass above the
      // horizon, and at least one reasonably high one.
      expect(sawAbove, isTrue, reason: 'no ISS pass found in 24 h over London');
      expect(maxEl, greaterThan(20.0),
          reason: 'best pass only reached ${maxEl.toStringAsFixed(1)} deg');
    });

    test('sub-point of the ISS tracks under the orbit within its altitude band',
        () {
      final sat = Sgp4Satellite(iss);
      final st = sat.propagate(0)!;
      final jd = iss.epochJd;
      final ecef = temeToEcef(Vec3(st.x, st.y, st.z), gmstRadians(jd));
      final gp = subPoint(ecef);
      // Ground track latitude cannot exceed the inclination.
      expect(gp.latDeg.abs(), lessThanOrEqualTo(51.7));
      // ISS altitude band.
      expect(gp.altKm, inInclusiveRange(380.0, 460.0));
    });
  });
}
