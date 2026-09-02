import 'package:flutter_test/flutter_test.dart';
import 'package:goldenscout/tool/astro.dart';

/// Reference times from timeanddate.com (rounded to the minute). The old
/// tests only asserted shapes ("sunrise exists"); a coefficient typed wrong
/// by one digit passed them. These pin the actual clock.
void main() {
  String hm(DateTime? t) => t == null
      ? '—'
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Matcher within(String hhmm, {int minutes = 2}) => predicate<String>((s) {
        if (s == '—') return false;
        int mins(String v) => int.parse(v.split(':')[0]) * 60 + int.parse(v.split(':')[1]);
        return (mins(s) - mins(hhmm)).abs() <= minutes;
      }, 'within $minutes min of $hhmm');

  test('Beijing, 2026-06-21 (UTC+8): sunrise 04:46, sunset 19:47', () {
    final d = computeDayLight(DateTime(2026, 6, 21), 39.9042, 116.4074,
        zoneOverride: const Duration(hours: 8));
    expect(hm(d.sunrise.time), within('04:46'));
    expect(hm(d.sunset.time), within('19:47'));
    expect(d.dayOffset(d.sunrise.time!), 0);
    expect(d.dayOffset(d.sunset.time!), 0);
  });

  test('New York, 2026-06-21 viewed from far away (UTC-5 est.): 04:25 / 19:31',
      () {
    // EDT is UTC-4 (05:25 / 20:31); the longitude estimate has no DST so the
    // app shows UTC-5 and labels it as estimated. Both morning and evening
    // events must exist — the old device-midnight window lost the mornings.
    final d = computeDayLight(DateTime(2026, 6, 21), 40.7128, -74.0060,
        zoneOverride: const Duration(hours: -5));
    expect(d.zoneEstimated, isTrue);
    expect(hm(d.dawnCivil.time), isNot('—'));
    expect(hm(d.sunrise.time), within('04:25'));
    expect(hm(d.sunset.time), within('19:31'));
    expect(hm(d.duskCivil.time), isNot('—'));
  });

  test('Reykjavik, 2026-06-21 (UTC+0): sunrise 02:55, sunset 00:04 next day',
      () {
    final d = computeDayLight(DateTime(2026, 6, 21), 64.1355, -21.8954,
        zoneOverride: Duration.zero);
    expect(d.polarDay, isFalse);
    expect(hm(d.sunrise.time), within('02:55', minutes: 3));
    expect(hm(d.sunset.time), within('00:04', minutes: 3));
    expect(d.dayOffset(d.sunset.time!), 1);
    // The Sun only dips to about −2.4° that night, so the evening blue hour
    // (−4°) genuinely never starts — and the app must say so, not invent it.
    expect(d.goldenEndPm.exists, isFalse);
    expect(d.duskCivil.exists, isFalse);
  });

  test('London, 2026-06-21 (UTC+1 est.): sunset side present', () {
    final d = computeDayLight(DateTime(2026, 6, 21), 51.5074, -0.1278,
        zoneOverride: const Duration(hours: 1));
    expect(hm(d.sunrise.time), within('04:43'));
    expect(hm(d.sunset.time), within('21:21'));
  });

  test('Tromsø in December is polar night, with no ghost sunrise', () {
    final d = computeDayLight(DateTime(2026, 12, 21), 69.6496, 18.9560,
        zoneOverride: const Duration(hours: 1));
    expect(d.polarNight, isTrue);
    expect(d.sunrise.exists, isFalse);
    // Civil twilight still exists there in December — the UI must not hide it.
    expect(d.dawnCivil.exists, isTrue);
  });

  test('zoneForLocation: nearby uses the device zone, far away estimates', () {
    final date = DateTime(2026, 6, 21);
    final device = date.timeZoneOffset;
    // A longitude matching the device zone exactly → device zone, not estimated.
    final sameLon = device.inMinutes / 60 * 15;
    expect(zoneForLocation(sameLon, date).estimated, isFalse);
    // 180° away is never within 2.5 h.
    final far = (sameLon + 180) > 180 ? sameLon - 180 : sameLon + 180;
    expect(zoneForLocation(far, date).estimated, isTrue);
    expect(zoneForLocation(far, date, forceDevice: true).estimated, isFalse);
  });
}
