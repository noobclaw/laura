import 'package:flutter_test/flutter_test.dart';
import 'package:fieldstamp/tool/geo_format.dart';
import 'package:fieldstamp/tool/models.dart';

void main() {
  group('formatLatLon', () {
    test('decimal degrees with 6 dp', () {
      expect(
        formatLatLon(37.7749, -122.4194, CoordFormat.decimal),
        '37.774900, -122.419400',
      );
    });

    test('null coordinates report no fix', () {
      expect(formatLatLon(null, null, CoordFormat.decimal), 'No GPS fix');
      expect(formatLatLon(1.0, null, CoordFormat.dms), 'No GPS fix');
    });

    test('DMS uses N/S and E/W hemispheres', () {
      final s = formatLatLon(-33.8688, 151.2093, CoordFormat.dms);
      expect(s.contains('S'), isTrue);
      expect(s.contains('E'), isTrue);
      expect(s.startsWith('33°'), isTrue);
    });
  });

  group('formatAltitude', () {
    test('meters', () {
      expect(formatAltitude(123.4, AltUnit.meters), '123 m');
    });
    test('feet conversion', () {
      expect(formatAltitude(100, AltUnit.feet), '328 ft');
    });
    test('null altitude', () {
      expect(formatAltitude(null, AltUnit.meters), '—');
    });
  });

  group('formatHeading', () {
    test('cardinal directions map correctly', () {
      expect(formatHeading(0), '0° N');
      expect(formatHeading(90), '90° E');
      expect(formatHeading(180), '180° S');
      expect(formatHeading(270), '270° W');
    });
    test('wraps negatives and >360', () {
      expect(formatHeading(-90), '270° W');
      expect(formatHeading(360), '0° N');
    });
    test('intercardinal rounding', () {
      expect(formatHeading(45), '45° NE');
      expect(formatHeading(135), '135° SE');
    });
    test('null heading', () {
      expect(formatHeading(null), '—');
    });
  });

  group('formatTimestamp', () {
    test('zero-pads fields', () {
      final t = DateTime(2026, 7, 5, 9, 3, 7);
      expect(formatTimestamp(t), '2026-07-05 09:03:07');
    });
  });

  group('csvField', () {
    test('leaves plain values untouched', () {
      expect(csvField('site A'), 'site A');
    });
    test('quotes and escapes values with commas or quotes', () {
      expect(csvField('a,b'), '"a,b"');
      expect(csvField('he said "hi"'), '"he said ""hi"""');
    });
  });

  group('StampPhoto json', () {
    test('round-trips all fields', () {
      final p = StampPhoto(
        id: 'img-1',
        fileName: 'img-1.jpg',
        projectId: 'proj-1',
        capturedAt: DateTime(2026, 7, 5, 12, 0, 0),
        latitude: 1.23,
        longitude: 4.56,
        altitude: 30.0,
        accuracy: 5.0,
        heading: 90.0,
        note: 'crack in wall',
      );
      final back = StampPhoto.fromJson(p.toJson());
      expect(back.id, p.id);
      expect(back.fileName, p.fileName);
      expect(back.projectId, p.projectId);
      expect(back.capturedAt, p.capturedAt);
      expect(back.latitude, p.latitude);
      expect(back.longitude, p.longitude);
      expect(back.altitude, p.altitude);
      expect(back.accuracy, p.accuracy);
      expect(back.heading, p.heading);
      expect(back.note, p.note);
      expect(back.hasFix, isTrue);
    });

    test('missing coordinates leave hasFix false', () {
      final p = StampPhoto(
        id: 'img-2',
        fileName: 'img-2.jpg',
        projectId: 'default',
        capturedAt: DateTime(2026, 1, 1),
      );
      expect(p.hasFix, isFalse);
      final back = StampPhoto.fromJson(p.toJson());
      expect(back.hasFix, isFalse);
    });
  });
}
