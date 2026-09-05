import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:picbox/tool/engine/image_probe.dart';
import 'package:picbox/tool/engine/metadata.dart';
import 'package:picbox/tool/models.dart';

img.Image _sample() {
  final im = img.Image(width: 24, height: 16);
  for (final p in im) {
    p
      ..r = p.x * 10
      ..g = p.y * 15
      ..b = 128;
  }
  return im;
}

Uint8List _jpegWithExif({bool gps = true}) {
  final im = _sample();
  im.exif.imageIfd['Make'] = img.IfdValueAscii('TestCam');
  im.exif.imageIfd['Model'] = img.IfdValueAscii('X-1');
  im.exif.imageIfd['Software'] = img.IfdValueAscii('unit-test');
  im.exif.imageIfd.orientation = 6;
  if (gps) {
    im.exif.gpsIfd[0x0001] = img.IfdValueAscii('N');
    im.exif.gpsIfd[0x0002] = _rat3(31, 1, 13, 1, 4800, 100);
    im.exif.gpsIfd[0x0003] = img.IfdValueAscii('E');
    im.exif.gpsIfd[0x0004] = _rat3(121, 1, 28, 1, 1200, 100);
  }
  return img.encodeJpg(im, quality: 80);
}

/// Three rationals as an IFD value (little-endian uint32 pairs).
img.IfdValueRational _rat3(int n1, int d1, int n2, int d2, int n3, int d3) {
  final b = ByteData(24);
  for (final (i, v) in [n1, d1, n2, d2, n3, d3].indexed) {
    b.setUint32(i * 4, v, Endian.little);
  }
  return img.IfdValueRational.data(img.InputBuffer(b.buffer.asUint8List()), 3);
}

void main() {
  group('sniff / probe', () {
    test('detects jpeg, png, webp', () {
      expect(sniffFormat(img.encodeJpg(_sample())), 'jpeg');
      expect(sniffFormat(img.encodePng(_sample())), 'png');
      expect(sniffFormat(img.encodeWebP(_sample())), 'webp');
      expect(sniffFormat(Uint8List.fromList([1, 2, 3])), 'unknown');
    });

    test('probe reports upright size for rotated EXIF orientation', () {
      final p = probeImage(_jpegWithExif());
      expect(p.format, ImageFormat.jpeg);
      // 24×16 stored, orientation 6 → shown as 16×24.
      expect((p.width, p.height), (16, 24));
      final plain = probeImage(img.encodeJpg(_sample()));
      expect((plain.width, plain.height), (24, 16));
    });

    test('probe flags png alpha', () {
      final rgba = img.Image(width: 4, height: 4, numChannels: 4);
      expect(probeImage(img.encodePng(rgba)).hasAlpha, isTrue);
      expect(probeImage(img.encodePng(_sample())).hasAlpha, isFalse);
    });
  });

  group('inspect', () {
    test('reads camera tags and GPS position from jpeg', () {
      final r = inspectMetadata(_jpegWithExif());
      expect(r.format, 'jpeg');
      expect(r.blocks, contains('EXIF'));
      expect(r.hasGps, isTrue);
      expect(r.latitude, closeTo(31.23, 0.001));
      expect(r.longitude, closeTo(121.47, 0.001));
      expect(r.entries.any((e) => e.key == 'Make' && e.value == 'TestCam'), isTrue);
      expect(r.entries.any((e) => e.key == 'GPSPosition'), isTrue);
      expect(r.tagCount, greaterThan(4));
    });

    test('jpeg without exif is empty', () {
      final r = inspectMetadata(img.encodeJpg(_sample()));
      expect(r.tagCount, 0);
      expect(r.hasGps, isFalse);
    });

    test('png text chunks are listed', () {
      final im = _sample()..textData = {'Comment': 'hello', 'Author': 'me'};
      final r = inspectMetadata(img.encodePng(im));
      expect(r.blocks, contains('Text'));
      expect(r.entries.where((e) => e.group == 'text').length, 2);
    });

    test('southern / western hemispheres are negative', () {
      final im = _sample();
      im.exif.gpsIfd[0x0001] = img.IfdValueAscii('S');
      im.exif.gpsIfd[0x0002] = _rat3(33, 1, 52, 1, 0, 1);
      im.exif.gpsIfd[0x0003] = img.IfdValueAscii('W');
      im.exif.gpsIfd[0x0004] = _rat3(151, 1, 12, 1, 0, 1);
      final r = inspectMetadata(img.encodeJpg(im));
      expect(r.latitude, closeTo(-33.8667, 0.001));
      expect(r.longitude, closeTo(-151.2, 0.001));
    });
  });

  group('strip', () {
    test('jpeg: removes EXIF/GPS, keeps pixels decodable and identical', () {
      final src = _jpegWithExif();
      final out = stripMetadata(src)!;
      expect(out.length, lessThan(src.length));
      final r = inspectMetadata(out);
      expect(r.tagCount, 0);
      expect(r.hasGps, isFalse);
      expect(r.blocks, isEmpty);
      expect(r.isEmpty, isTrue);
      // The orientation survives (it is the one tag a lossless strip must
      // keep, or the photo would display sideways)…
      expect(img.decodeJpgExif(out)!.imageIfd.orientation, 6);
      // …and nothing else does.
      expect(img.decodeJpgExif(out)!.imageIfd.keys.length, 1);
      expect(img.decodeJpgExif(out)!.gpsIfd.isEmpty, isTrue);
      final a = img.decodeJpg(src)!;
      final b = img.decodeJpg(out)!;
      expect((b.width, b.height), (a.width, a.height));
      // Entropy data untouched → identical pixels.
      expect(b.getPixel(5, 5), a.getPixel(5, 5));
      expect(b.getPixel(20, 3), a.getPixel(20, 3));
      expect(out.sublist(out.length - 2), [0xFF, 0xD9]);
    });

    test('jpeg: keeps JFIF and ICC APP segments, drops COM', () {
      final src = _jpegWithExif();
      // Splice a COM segment and an ICC APP2 segment right after SOI.
      final com = [0xFF, 0xFE, 0x00, 0x07, ...'hello'.codeUnits];
      final iccPayload = [...'ICC_PROFILE'.codeUnits, 0, 1, 1, 9, 9, 9];
      final icc = [0xFF, 0xE2, 0x00, iccPayload.length + 2, ...iccPayload];
      final spliced = Uint8List.fromList([...src.sublist(0, 2), ...com, ...icc, ...src.sublist(2)]);
      final before = inspectMetadata(spliced);
      expect(before.blocks, containsAll(['Comment', 'ICC', 'EXIF']));
      final out = stripMetadata(spliced)!;
      final after = inspectMetadata(out);
      expect(after.blocks, ['ICC']);
      expect(img.decodeJpg(out), isNotNull);
    });

    test('jpeg: trailing bytes after EOI are cut', () {
      final src = _jpegWithExif();
      final withTrailer = Uint8List.fromList([...src, ...List.filled(500, 0x42)]);
      expect(inspectMetadata(withTrailer).blocks, contains('Trailer'));
      final out = stripMetadata(withTrailer)!;
      expect(out.length, lessThan(src.length));
      expect(out.sublist(out.length - 2), [0xFF, 0xD9]);
    });

    test('png: drops text/eXIf/tIME chunks, keeps image', () {
      final im = _sample()..textData = {'Comment': 'secret'};
      im.exif.imageIfd['Make'] = img.IfdValueAscii('TestCam');
      final src = img.encodePng(im);
      expect(inspectMetadata(src).blocks, contains('Text'));
      final out = stripMetadata(src)!;
      final r = inspectMetadata(out);
      expect(r.blocks, isEmpty);
      expect(r.tagCount, 0);
      final dec = img.decodePng(out)!;
      expect((dec.width, dec.height), (24, 16));
      expect(dec.getPixel(3, 3), img.decodePng(src)!.getPixel(3, 3));
    });

    test('webp: EXIF chunk removed and RIFF size fixed', () {
      final base = img.encodeWebP(_sample());
      // Append an EXIF chunk (odd length → padded) and fix the RIFF size.
      final exifPayload = [...'Exif\x00\x00'.codeUnits, 0x49, 0x49, 0x2A, 0x00, 0x08, 0, 0, 0, 0, 0, 1];
      final len = exifPayload.length;
      final chunk = [
        ...'EXIF'.codeUnits,
        len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF, (len >> 24) & 0xFF,
        ...exifPayload,
        if (len.isOdd) 0,
      ];
      final withExif = Uint8List.fromList([...base, ...chunk]);
      final total = withExif.length - 8;
      withExif[4] = total & 0xFF;
      withExif[5] = (total >> 8) & 0xFF;
      withExif[6] = (total >> 16) & 0xFF;
      withExif[7] = (total >> 24) & 0xFF;
      expect(inspectMetadata(withExif).blocks, contains('EXIF'));
      final out = stripMetadata(withExif)!;
      expect(out.length, base.length);
      expect(inspectMetadata(out).blocks, isEmpty);
      final riffSize = out[4] | (out[5] << 8) | (out[6] << 16) | (out[7] << 24);
      expect(riffSize, out.length - 8);
      expect(img.decodeWebP(out), isNotNull);
    });

    test('unknown container returns null', () {
      expect(stripMetadata(Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])), isNull);
    });
  });
}
