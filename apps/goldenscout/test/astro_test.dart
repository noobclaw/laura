import 'package:flutter_test/flutter_test.dart';
import 'package:goldenscout/tool/astro.dart';

// These tests exercise the UTC-based astronomy directly (timezone-independent)
// plus timezone-robust properties of computeDayLight (polar flags, event
// ordering, rise/set azimuths). Tolerances are generous enough to absorb the
// low-precision ephemeris (~1' sun, ~2' moon) yet tight enough to catch real
// regressions: wrong hemisphere, flipped direction, or broken threshold logic.

void main() {
  group('normDeg', () {
    test('wraps into [0,360)', () {
      expect(normDeg(0), 0);
      expect(normDeg(360), 0);
      expect(normDeg(370), 10);
      expect(normDeg(-10), 350);
      expect(normDeg(-370), 350);
    });
  });

  group('compassLabel', () {
    test('cardinal and intercardinal points', () {
      expect(compassLabel(0), 'N');
      expect(compassLabel(90), 'E');
      expect(compassLabel(180), 'S');
      expect(compassLabel(270), 'W');
      expect(compassLabel(45), 'NE');
      expect(compassLabel(200), 'SSW');
      expect(compassLabel(359), 'N'); // wraps back to North
    });
  });

  group('dayNumber', () {
    test('Schlyter epoch: 2000-01-01 00:00 UT is day 1', () {
      expect(dayNumber(DateTime.utc(2000, 1, 1, 0, 0, 0)), closeTo(1.0, 1e-6));
    });
    test('advances by one per day and by 0.5 per 12h', () {
      final a = dayNumber(DateTime.utc(2026, 6, 1, 0));
      final b = dayNumber(DateTime.utc(2026, 6, 2, 0));
      final c = dayNumber(DateTime.utc(2026, 6, 1, 12));
      expect(b - a, closeTo(1.0, 1e-9));
      expect(c - a, closeTo(0.5, 1e-9));
    });
  });

  group('sunPosition (equator, equinox)', () {
    // 2026 March equinox ~ Mar 20. At the equator the noon Sun is near zenith,
    // rises due east and sets due west.
    test('near zenith at local noon', () {
      final p = sunPosition(DateTime.utc(2026, 3, 20, 12), 0, 0);
      expect(p.altitude, greaterThan(80));
    });
    test('below the horizon at local midnight', () {
      final p = sunPosition(DateTime.utc(2026, 3, 20, 0), 0, 0);
      expect(p.altitude, lessThan(0));
    });
    test('rises roughly due east', () {
      final p = sunPosition(DateTime.utc(2026, 3, 20, 6), 0, 0);
      expect(p.altitude, closeTo(0, 6));
      expect(p.azimuth, closeTo(90, 15));
    });
    test('sets roughly due west', () {
      final p = sunPosition(DateTime.utc(2026, 3, 20, 18), 0, 0);
      expect(p.altitude, closeTo(0, 6));
      expect(p.azimuth, closeTo(270, 15));
    });
  });

  group('sunPosition (hemisphere azimuth)', () {
    test('northern midlatitude noon Sun is to the south', () {
      // London-ish (51.5N, 0E), solar noon ~12:00 UTC.
      final p = sunPosition(DateTime.utc(2026, 6, 21, 12), 51.5, 0);
      expect(p.altitude, greaterThan(0));
      expect(p.azimuth, closeTo(180, 25));
    });
    test('southern midlatitude noon Sun is to the north', () {
      // Sydney (33.86S, 151.2E), solar noon ~01:55 UTC.
      final p = sunPosition(DateTime.utc(2026, 6, 21, 2), -33.86, 151.2);
      expect(p.altitude, greaterThan(0));
      final az = p.azimuth;
      expect(az < 30 || az > 330, isTrue, reason: 'expected northerly azimuth, got $az');
    });
  });

  group('moonPhase', () {
    test('new moon 2024-01-11 is barely illuminated', () {
      final ph = moonPhase(DateTime.utc(2024, 1, 11, 12));
      expect(ph.illumination, lessThan(0.10));
      expect(ph.name,
          anyOf('New Moon', 'Waxing Crescent', 'Waning Crescent'));
    });
    test('full moon 2024-01-25 is nearly fully illuminated', () {
      final ph = moonPhase(DateTime.utc(2024, 1, 25, 18));
      expect(ph.illumination, greaterThan(0.95));
      expect(ph.name,
          anyOf('Full Moon', 'Waxing Gibbous', 'Waning Gibbous'));
    });
    test('illumination stays within [0,1] across a synodic month', () {
      for (var d = 0; d < 30; d++) {
        final ph = moonPhase(DateTime.utc(2026, 1, 1).add(Duration(days: d)));
        expect(ph.illumination, inInclusiveRange(0.0, 1.0));
        expect(ph.elongation, inInclusiveRange(0.0, 360.0));
      }
    });
  });

  group('moonPosition', () {
    test('returns finite, in-range values', () {
      final p = moonPosition(DateTime.utc(2026, 7, 21, 20), 40, -74);
      expect(p.azimuth, inInclusiveRange(0.0, 360.0));
      expect(p.altitude, inInclusiveRange(-90.0, 90.0));
    });
  });

  group('computeDayLight polar cases', () {
    test('high arctic in June is midnight sun (polar day)', () {
      final d = computeDayLight(DateTime(2026, 6, 21), 85, 0);
      expect(d.polarDay, isTrue);
      expect(d.polarNight, isFalse);
      expect(d.sunrise.exists, isFalse);
    });
    test('high arctic in December is polar night', () {
      final d = computeDayLight(DateTime(2026, 12, 21), 85, 0);
      expect(d.polarNight, isTrue);
      expect(d.polarDay, isFalse);
      expect(d.noonAltitude, lessThan(SunAltitudes.sunrise));
    });
  });

  group('computeDayLight ordering + rise/set direction', () {
    // computeDayLight builds the day from local midnight and assumes solar noon
    // sits near the middle of that window — true whenever the location's
    // longitude matches the device timezone (the real current-location use
    // case). To reproduce that regardless of the runner's timezone, place the
    // test location at the longitude aligned to the runner's UTC offset.
    final tzHours = DateTime.now().timeZoneOffset.inMinutes / 60.0;
    final alignedLon = (tzHours * 15).clamp(-179.0, 179.0);

    test('finds a sunrise (~east) and sunset (~west) at the equator equinox', () {
      final d = computeDayLight(DateTime(2026, 3, 20), 0, alignedLon);
      expect(d.sunrise.exists, isTrue, reason: 'no sunrise found');
      expect(d.sunset.exists, isTrue, reason: 'no sunset found');
      expect(d.sunrise.azimuth!, closeTo(90, 15));
      expect(d.sunset.azimuth!, closeTo(270, 15));
      // ~12h of daylight at the equator on the equinox.
      expect(d.daylight!.inMinutes, closeTo(720, 20));
    });

    test('twilight moments are monotonically ordered within a day', () {
      // Midlatitude summer day (tz-aligned longitude) guarantees all moments.
      final d = computeDayLight(DateTime(2026, 6, 21), 40, alignedLon);
      final seq = <DateTime>[
        if (d.dawnCivil.time != null) d.dawnCivil.time!,
        if (d.goldenStartAm.time != null) d.goldenStartAm.time!,
        if (d.sunrise.time != null) d.sunrise.time!,
        if (d.goldenEndAm.time != null) d.goldenEndAm.time!,
        if (d.solarNoon != null) d.solarNoon!,
        if (d.goldenStartPm.time != null) d.goldenStartPm.time!,
        if (d.sunset.time != null) d.sunset.time!,
        if (d.goldenEndPm.time != null) d.goldenEndPm.time!,
        if (d.duskCivil.time != null) d.duskCivil.time!,
      ];
      expect(seq.length, greaterThanOrEqualTo(7));
      for (var i = 1; i < seq.length; i++) {
        expect(seq[i].isAfter(seq[i - 1]), isTrue,
            reason: 'moment $i not after ${i - 1}: $seq');
      }
      // Morning golden hour brackets sunrise; sunrise is eastward.
      expect(d.sunrise.azimuth!, inInclusiveRange(30.0, 130.0));
      expect(d.sunset.azimuth!, inInclusiveRange(230.0, 330.0));
    });
  });
}
