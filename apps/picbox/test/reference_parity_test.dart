// Reference-parity checks (PIPELINE G8c) against ImageToolbox (T8RIN,
// Apache-2.0). See apps/picbox/REFERENCE.md for the full function-level
// audit. These tests pin the two behaviours the audit chose to keep
// bit-faithful to the reference spec:
//
//   1. The metadata strip removes every privacy-bearing block (EXIF tags,
//      XMP, GPS, PNG text, WebP XMP) yet keeps the single EXIF Orientation
//      tag so a phone photo is not displayed sideways. ICC is deliberately
//      retained for colour fidelity (documented deviation).
//   2. The compress-to-size search is monotone and honours the reference's
//      byte-target normalisation: a smaller target never yields a larger
//      file, and every result lands at or under its target.
//
// All sample images are generated in-process with `package:image`; nothing
// reads an external file.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:picbox/tool/engine/metadata.dart';
import 'package:picbox/tool/engine/size_search.dart';

// ---------------------------------------------------------------------------
// Sample builders
// ---------------------------------------------------------------------------

img.Image _photo(int w, int h) {
  // Pseudo-random per-pixel noise so JPEG cannot collapse it to a few KB;
  // deterministic seed keeps byte sizes stable across runs.
  final im = img.Image(width: w, height: h);
  var s = 0x2545F491;
  int next() {
    s ^= s << 13;
    s ^= s >>> 17;
    s ^= s << 5;
    return s & 0xFF;
  }

  for (final p in im) {
    p
      ..r = next()
      ..g = next()
      ..b = next();
  }
  return im;
}

/// A JPEG APP segment: marker byte + big-endian length + payload.
List<int> _appSegment(int marker, List<int> payload) {
  final len = payload.length + 2;
  return [0xFF, marker, len >> 8, len & 0xFF, ...payload];
}

/// JPEG carrying EXIF (orientation 6 + GPS + Make), an XMP APP1 and an ICC
/// APP2 — the three block families the audit cares about.
Uint8List _jpegWithEverything() {
  final im = _photo(64, 48);
  im.exif.imageIfd['Make'] = img.IfdValueAscii('TestCam');
  im.exif.imageIfd['Model'] = img.IfdValueAscii('X-1');
  im.exif.imageIfd.orientation = 6;
  im.exif.gpsIfd[0x0001] = img.IfdValueAscii('N');
  im.exif.gpsIfd[0x0002] = _rat3(31, 1, 13, 1, 4800, 100);
  im.exif.gpsIfd[0x0003] = img.IfdValueAscii('E');
  im.exif.gpsIfd[0x0004] = _rat3(121, 1, 28, 1, 1200, 100);
  final base = img.encodeJpg(im, quality: 90);

  final xmp = _appSegment(
      0xE1,
      [
        ...'http://ns.adobe.com/xap/1.0/\x00'.codeUnits,
        ...'<x:xmpmeta><gps>secret</gps></x:xmpmeta>'.codeUnits,
      ]);
  final icc = _appSegment(0xE2, [...'ICC_PROFILE'.codeUnits, 0, 1, 1, 9, 9, 9, 9, 9]);
  // Splice both right after SOI (bytes 0..1), before the encoder's own APP0.
  return Uint8List.fromList([...base.sublist(0, 2), ...xmp, ...icc, ...base.sublist(2)]);
}

img.IfdValueRational _rat3(int n1, int d1, int n2, int d2, int n3, int d3) {
  final b = ByteData(24);
  for (final (i, v) in [n1, d1, n2, d2, n3, d3].indexed) {
    b.setUint32(i * 4, v, Endian.little);
  }
  return img.IfdValueRational.data(img.InputBuffer(b.buffer.asUint8List()), 3);
}

/// PNG carrying a tEXt chunk (via textData), an eXIf chunk (via exif) and a
/// spliced iTXt chunk. CRCs on the spliced chunk are irrelevant: the strip
/// and the inspector read by length only, and pixels are decoded from the
/// stripped output where the chunk is already gone.
Uint8List _pngWithEverything() {
  final im = _photo(40, 30)..textData = {'Comment': 'private note', 'Author': 'me'};
  final base = img.encodePng(im);

  // A PNG chunk with a dummy CRC (never validated on the strip/inspect path,
  // and gone from the pixels-decoded output).
  List<int> chunk(String type, List<int> data) {
    final len = data.length;
    return [
      (len >> 24) & 0xFF, (len >> 16) & 0xFF, (len >> 8) & 0xFF, len & 0xFF,
      ...type.codeUnits,
      ...data,
      0, 0, 0, 0,
    ];
  }

  // iTXt: keyword\0 compFlag compMethod lang\0 translated\0 text.
  final iTXt = chunk('iTXt',
      [...'XML:com.adobe.xmp'.codeUnits, 0, 0, 0, 0, 0, ...'geo:1,2'.codeUnits]);
  // eXIf: a minimal little-endian TIFF header (encodePng does not emit one).
  final eXIf = chunk('eXIf', [0x49, 0x49, 0x2A, 0x00, 0x08, 0, 0, 0, 0, 0]);
  // Insert after the 8-byte signature + IHDR (25 bytes) = offset 33.
  return Uint8List.fromList(
      [...base.sublist(0, 33), ...iTXt, ...eXIf, ...base.sublist(33)]);
}

/// WebP carrying an EXIF chunk and an XMP chunk appended to the RIFF.
Uint8List _webpWithEverything() {
  final base = img.encodeWebP(_photo(48, 32));
  List<int> chunk(String fourcc, List<int> payload) {
    final len = payload.length;
    return [
      ...fourcc.codeUnits,
      len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF, (len >> 24) & 0xFF,
      ...payload,
      if (len.isOdd) 0,
    ];
  }

  final exif = chunk('EXIF',
      [...'Exif\x00\x00'.codeUnits, 0x49, 0x49, 0x2A, 0x00, 0x08, 0, 0, 0, 0, 0, 1]);
  final xmp = chunk('XMP ', '<x:xmpmeta>gps here</x:xmpmeta>'.codeUnits);
  final out = Uint8List.fromList([...base, ...exif, ...xmp]);
  final total = out.length - 8;
  out[4] = total & 0xFF;
  out[5] = (total >> 8) & 0xFF;
  out[6] = (total >> 16) & 0xFF;
  out[7] = (total >> 24) & 0xFF;
  return out;
}

void main() {
  group('metadata strip parity: only Orientation survives', () {
    test('jpeg: EXIF/XMP/GPS gone, Orientation kept, ICC deliberately kept', () {
      final src = _jpegWithEverything();
      final before = inspectMetadata(src);
      expect(before.blocks, containsAll(['EXIF', 'XMP', 'ICC']));
      expect(before.hasGps, isTrue);

      final out = stripMetadata(src)!;
      final after = inspectMetadata(out);
      // No privacy metadata is reported: an orientation-only EXIF is treated
      // as empty by the inspector, XMP is gone, GPS is gone.
      expect(after.hasGps, isFalse);
      expect(after.blocks, isNot(contains('EXIF')));
      expect(after.blocks, isNot(contains('XMP')));
      expect(after.entries.any((e) => e.key == 'Make'), isFalse);
      // The one EXIF tag that must remain is Orientation, and nothing else.
      final exif = img.decodeJpgExif(out)!;
      expect(exif.imageIfd.orientation, 6);
      expect(exif.imageIfd.keys.length, 1);
      expect(exif.gpsIfd.isEmpty, isTrue);
      // ICC is retained on purpose (colour fidelity) — documented deviation.
      expect(after.blocks, contains('ICC'));
      expect(img.decodeJpg(out), isNotNull);
      expect(out.sublist(out.length - 2), [0xFF, 0xD9]);
    });

    test('png: tEXt/iTXt/eXIf all removed, pixels identical', () {
      final src = _pngWithEverything();
      final before = inspectMetadata(src);
      expect(before.blocks, contains('Text'));
      expect(before.blocks, contains('EXIF'));

      final out = stripMetadata(src)!;
      final after = inspectMetadata(out);
      expect(after.blocks, isEmpty);
      expect(after.tagCount, 0);
      expect(after.isEmpty, isTrue);

      final a = img.decodePng(src)!;
      final b = img.decodePng(out)!;
      expect((b.width, b.height), (a.width, a.height));
      expect(b.getPixel(7, 7), a.getPixel(7, 7));
    });

    test('webp: EXIF and XMP chunks removed, RIFF size fixed, still decodes', () {
      final src = _webpWithEverything();
      expect(inspectMetadata(src).blocks, containsAll(['EXIF', 'XMP']));

      final out = stripMetadata(src)!;
      expect(inspectMetadata(out).blocks, isEmpty);
      final riffSize = out[4] | (out[5] << 8) | (out[6] << 16) | (out[7] << 24);
      expect(riffSize, out.length - 8);
      expect(img.decodeWebP(out), isNotNull);
    });
  });

  group('compress-to-size parity: monotone, at or under target', () {
    // A real pure-Dart JPEG probe (no native codec in flutter test): encode
    // the source at the search's quality, shrinking pixels by `scale` first.
    final source = _photo(400, 400);

    Future<SizeSearchResult> searchTo(int targetBytes) => searchForTargetSize(
          targetBytes: targetBytes,
          // Same floor the runtime uses (matches the reference's 15).
          minQuality: 15,
          maxQuality: 95,
          startQuality: 85,
          probe: (p) {
            final im = p.scale >= 0.999
                ? source
                : img.copyResize(source,
                    width: (source.width * p.scale).round().clamp(1, source.width),
                    interpolation: img.Interpolation.average);
            return img.encodeJpg(im, quality: p.quality).length;
          },
        );

    test('200 KB result is ≤ 200 KB and ≥ the 120 KB result', () async {
      final big = await searchTo(200 * 1024);
      final small = await searchTo(120 * 1024);
      expect(big.hitTarget, isTrue);
      expect(small.hitTarget, isTrue);
      expect(big.bytes, lessThanOrEqualTo(200 * 1024));
      expect(small.bytes, lessThanOrEqualTo(120 * 1024));
      // Monotone: a larger budget never produces a smaller file.
      expect(big.bytes, greaterThanOrEqualTo(small.bytes));
    });

    test('quality never probes below the reference floor of 15', () async {
      final seen = <int>[];
      await searchForTargetSize(
        targetBytes: 8 * 1024, // forces the search down to the floor + scaling
        minQuality: 15,
        maxQuality: 95,
        startQuality: 85,
        probe: (p) {
          seen.add(p.quality);
          final im = p.scale >= 0.999
              ? source
              : img.copyResize(source,
                  width: (source.width * p.scale).round().clamp(1, source.width),
                  interpolation: img.Interpolation.average);
          return img.encodeJpg(im, quality: p.quality).length;
        },
      );
      expect(seen, isNotEmpty);
      expect(seen.every((q) => q >= 15 && q <= 95), isTrue);
      expect(seen, contains(15));
    });
  });
}
