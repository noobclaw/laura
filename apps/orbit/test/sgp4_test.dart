import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/tool/astro.dart';
import 'package:orbit/tool/sgp4.dart';

/// The canonical SGP4 verification case from Spacetrack Report #3 / Vallado's
/// test suite. If the propagator is right, satellite 88888 lands on these state
/// vectors; if a single coefficient is transcribed wrongly it will not.
const String _vanguardName = 'TEST SAT 88888';
const String _vanguardL1 =
    '1 88888U          80275.98708465  .00073094  13844-3  66816-4 0    87';
const String _vanguardL2 =
    '2 88888  72.8435 115.9689 0086731  52.6988 110.5714 16.05824518  1058';

void main() {
  group('TLE parsing', () {
    test('reads every field of a real element set', () {
      final tle = Tle.parse(
        'ISS (ZARYA)',
        '1 25544U 98067A   26214.50635181  .00006342  00000+0  12183-3 0  9996',
        '2 25544  51.6315  70.8679 0007172   4.7554 355.3502 15.49313226578933',
      );
      expect(tle, isNotNull);
      expect(tle!.satnum, '25544');
      expect(tle.name, 'ISS (ZARYA)');
      expect(tle.inclo * radToDeg, closeTo(51.6315, 1e-4));
      expect(tle.nodeo * radToDeg, closeTo(70.8679, 1e-4));
      expect(tle.ecco, closeTo(0.0007172, 1e-9));
      expect(tle.argpo * radToDeg, closeTo(4.7554, 1e-4));
      expect(tle.mo * radToDeg, closeTo(355.3502, 1e-4));
      // 15.49313226 rev/day.
      expect(tle.noKozai * 1440 / (2 * math.pi), closeTo(15.49313226, 1e-8));
      // "12183-3" is 0.12183e-3, not 12183 and not 0.12183.
      expect(tle.bstar, closeTo(0.00012183, 1e-12));
      // Epoch 26214.50635181 = 2026-08-02 12:09:08 UTC.
      final epoch = dateTimeFromJulian(tle.epochJd);
      expect(epoch.year, 2026);
      expect(epoch.month, 8);
      expect(epoch.day, 2);
      expect(epoch.hour, 12);
      expect(tle.isDeepSpace, isFalse);
    });

    test('rejects malformed input instead of throwing', () {
      expect(Tle.parse('X', 'garbage', 'more garbage'), isNull);
      expect(Tle.parse('X', '1 25544U 98067A', '2 25544'), isNull);
      // Mismatched satellite numbers between the two lines.
      expect(
        Tle.parse(
          'X',
          '1 25544U 98067A   26214.50635181  .00006342  00000+0  12183-3 0  9996',
          '2 25545  51.6315  70.8679 0007172   4.7554 355.3502 15.49313226578933',
        ),
        isNull,
      );
    });

    test('parseAll survives blank lines, CRLF and stray prose', () {
      const text = '\r\n'
          'ISS (ZARYA)\r\n'
          '1 25544U 98067A   26214.50635181  .00006342  00000+0  12183-3 0  9996\r\n'
          '2 25544  51.6315  70.8679 0007172   4.7554 355.3502 15.49313226578933\r\n'
          '\r\n'
          'HST\r\n'
          '1 20580U 90037B   26214.16388447  .00005559  00000+0  17148-3 0  9997\r\n'
          '2 20580  28.4694 179.5121 0002418 268.8425  91.1832 15.14063834782406\r\n';
      final list = Tle.parseAll(text);
      expect(list.length, 2);
      expect(list[0].satnum, '25544');
      expect(list[1].satnum, '20580');
    });

    test('flags deep-space objects so the near-Earth model never sees them', () {
      // A geostationary element set: one revolution per day.
      final geo = Tle.parse(
        'GEO TEST',
        '1 40000U 14001A   26214.50000000  .00000000  00000+0  00000+0 0  9998',
        '2 40000   0.0200  95.0000 0002000 100.0000 260.0000  1.00270000 40007',
      );
      expect(geo, isNotNull);
      expect(geo!.isDeepSpace, isTrue);
    });
  });

  group('SGP4 propagation', () {
    test('matches the Spacetrack Report #3 reference vectors', () {
      final tle = Tle.parse(_vanguardName, _vanguardL1, _vanguardL2);
      expect(tle, isNotNull);
      final sat = Sgp4Satellite(tle!);
      expect(sat.usable, isTrue);

      final t0 = sat.propagate(0);
      expect(t0, isNotNull);
      // Reference: 2328.97048951, -5995.22076416, 1719.97067261 km
      //            2.91207230, -0.98341546, -7.09081703 km/s
      expect(t0!.x, closeTo(2328.97, 0.5));
      expect(t0.y, closeTo(-5995.22, 0.5));
      expect(t0.z, closeTo(1719.97, 0.5));
      expect(t0.vx, closeTo(2.91207, 0.001));
      expect(t0.vy, closeTo(-0.98342, 0.001));
      expect(t0.vz, closeTo(-7.09082, 0.001));

      final t360 = sat.propagate(360);
      expect(t360, isNotNull);
      // Reference: 2456.10705566, -6071.93853760, 1222.89727783 km
      expect(t360!.x, closeTo(2456.11, 1.0));
      expect(t360.y, closeTo(-6071.94, 1.0));
      expect(t360.z, closeTo(1222.90, 1.0));
    });

    test('keeps the orbit physically sane over a week', () {
      final tle = Tle.parse(
        'ISS (ZARYA)',
        '1 25544U 98067A   26214.50635181  .00006342  00000+0  12183-3 0  9996',
        '2 25544  51.6315  70.8679 0007172   4.7554 355.3502 15.49313226578933',
      )!;
      final sat = Sgp4Satellite(tle);
      for (var minutes = 0.0; minutes <= 7 * 1440; minutes += 37) {
        final s = sat.propagate(minutes);
        expect(s, isNotNull, reason: 'propagation failed at $minutes min');
        // The ISS lives between roughly 400 and 430 km up; allow a wide band
        // and still catch any coefficient blow-up.
        expect(s!.radiusKm, inInclusiveRange(6600, 6900));
        expect(s.speedKmPerSec, inInclusiveRange(7.0, 8.2));
      }
    });

    test('period recovered from the elements matches the mean motion', () {
      final tle = Tle.parse(
        'ISS (ZARYA)',
        '1 25544U 98067A   26214.50635181  .00006342  00000+0  12183-3 0  9996',
        '2 25544  51.6315  70.8679 0007172   4.7554 355.3502 15.49313226578933',
      )!;
      // 15.493 rev/day is a touch under 93 minutes per orbit.
      expect(tle.periodMinutes, closeTo(92.94, 0.05));
    });
  });

  group('time and frames', () {
    test('julian date round-trips', () {
      final t = DateTime.utc(2026, 8, 3, 17, 24, 36);
      final jd = julianDateOf(t);
      final back = dateTimeFromJulian(jd);
      expect(back.difference(t).inMilliseconds.abs(), lessThan(2));
    });

    test('J2000 epoch is julian date 2451545.0', () {
      expect(julianDateOf(DateTime.utc(2000, 1, 1, 12)), closeTo(2451545.0, 1e-6));
    });

    test('GMST advances one full turn per sidereal day', () {
      final jd = julianDateOf(DateTime.utc(2026, 8, 3));
      final a = gmstRadians(jd);
      final b = gmstRadians(jd + 1.0);
      // A solar day is about 1.0027 sidereal days, so GMST gains ~0.0172 rad.
      var delta = (b - a) % (2 * math.pi);
      if (delta < 0) delta += 2 * math.pi;
      expect(delta, closeTo(0.0172, 0.002));
    });

    test('observer at the equator/prime meridian sits on the +X axis', () {
      final v = observerEcef(0, 0, 0);
      expect(v.x, closeTo(earthRadiusKm, 0.001));
      expect(v.y, closeTo(0, 1e-9));
      expect(v.z, closeTo(0, 1e-9));
    });

    test('a point straight overhead reads 90 degrees elevation', () {
      final site = observerEcef(30, 120, 0);
      // Same direction, twice the distance: directly above the observer.
      final above = Vec3(site.x * 1.06, site.y * 1.06, site.z * 1.06);
      final look = lookAngles(above, site, 30, 120);
      expect(look.elevationDeg, closeTo(90, 0.5));
    });

    test('azimuth is measured clockwise from true north', () {
      final site = observerEcef(0, 0, 0);
      // Displace the target toward the north pole: bearing must read ~0.
      final north = Vec3(site.x, site.y, site.z + 1000);
      expect(lookAngles(north, site, 0, 0).azimuthDeg, closeTo(0, 1.0));
      // Displace toward +Y (east at lon 0): bearing must read ~90.
      final east = Vec3(site.x, site.y + 1000, site.z);
      expect(lookAngles(east, site, 0, 0).azimuthDeg, closeTo(90, 1.0));
    });

    test('sub-point of the observer is the observer', () {
      final site = observerEcef(31.23, 121.47, 0);
      final gp = subPoint(site);
      expect(gp.latDeg, closeTo(31.23, 0.01));
      expect(gp.lonDeg, closeTo(121.47, 0.01));
      expect(gp.altKm, closeTo(0, 1.0));
    });

    test('the sun is where an almanac says it is', () {
      // Northern summer: the sun sits well north of the equator, and at
      // local noon in Greenwich it is due south and high.
      final jd = julianDateOf(DateTime.utc(2026, 6, 21, 12));
      final elevation = sunElevationDeg(jd, 51.48, 0.0, 0.0);
      // London's midsummer noon sun is ~62 degrees up.
      expect(elevation, closeTo(62, 2.5));

      // Midwinter midnight in London: deeply below the horizon.
      final night = julianDateOf(DateTime.utc(2026, 12, 21, 0));
      expect(sunElevationDeg(night, 51.48, 0.0, 0.0), lessThan(-50));
    });

    test('visibility radius shrinks as the elevation bar is raised', () {
      final horizon = visibilityRadiusDeg(420, 0);
      final ten = visibilityRadiusDeg(420, 10);
      final thirty = visibilityRadiusDeg(420, 30);
      expect(horizon, greaterThan(ten));
      expect(ten, greaterThan(thirty));
      // A 420 km orbit reaches about 19.8 degrees of central angle at the
      // horizon — a well-known figure for ISS-height coverage.
      expect(horizon, closeTo(19.8, 0.5));
    });

    test('shadow test: midnight side eclipsed, day side lit', () {
      const sun = Vec3(149597870.7, 0, 0);
      // Directly behind the Earth from the Sun, at ISS height.
      expect(isSunlit(const Vec3(-6800, 0, 0), sun), isFalse);
      // Same distance but off to the side: outside the shadow cylinder.
      expect(isSunlit(const Vec3(-6800, 6800, 0), sun), isTrue);
      // Sunward hemisphere always lit.
      expect(isSunlit(const Vec3(6800, 0, 0), sun), isTrue);
    });

    test('magnitude brightens as the satellite gets closer', () {
      // Sun off to one side so the satellite is half lit as seen from the
      // ground; putting it directly behind the observer would be a zero-phase
      // geometry, where there is no lit face to see at all.
      const sun = Vec3(0, 149597870.7, 0);
      const observer = Vec3(6378, 0, 0);
      final near = apparentMagnitude(
        standardMagnitude: -1.8,
        satEci: const Vec3(6778, 0, 0),
        sunEci: sun,
        observerEci: observer,
        rangeKm: 400,
      );
      final far = apparentMagnitude(
        standardMagnitude: -1.8,
        satEci: const Vec3(8378, 0, 0),
        sunEci: sun,
        observerEci: observer,
        rangeKm: 2000,
      );
      expect(near, isNotNull);
      expect(far, isNotNull);
      expect(near!, lessThan(far!)); // smaller magnitude = brighter
      // A satellite lit from directly behind the observer shows us only its
      // night side: no magnitude claim is made.
      expect(
        apparentMagnitude(
          standardMagnitude: -1.8,
          satEci: const Vec3(6778, 0, 0),
          sunEci: const Vec3(149597870.7, 0, 0),
          observerEci: observer,
          rangeKm: 400,
        ),
        isNull,
      );
      // Nothing is invented for objects with no published standard magnitude.
      expect(
        apparentMagnitude(
          standardMagnitude: null,
          satEci: const Vec3(6778, 0, 0),
          sunEci: sun,
          observerEci: observer,
          rangeKm: 400,
        ),
        isNull,
      );
    });
  });
}
