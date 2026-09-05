import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// One line of the metadata preview shown before stripping.
class MetaEntry {
  const MetaEntry(this.group, this.key, this.value);

  /// `camera` / `time` / `gps` / `software` / `author` / `other` / `text`.
  final String group;

  /// Raw tag name (English, e.g. `DateTimeOriginal`); the UI localises a
  /// curated subset and shows the rest verbatim.
  final String key;
  final String value;
}

/// What a file carries besides pixels. Built without decoding the image.
class MetadataReport {
  const MetadataReport({
    required this.format,
    required this.entries,
    required this.tagCount,
    required this.hasGps,
    required this.latitude,
    required this.longitude,
    required this.blocks,
    required this.metaBytes,
  });

  /// `jpeg` / `png` / `webp` / `unknown`.
  final String format;
  final List<MetaEntry> entries;

  /// Total EXIF tags across all IFDs (the preview shows a subset).
  final int tagCount;
  final bool hasGps;
  final double? latitude;
  final double? longitude;

  /// Names of the non-pixel blocks found: `EXIF`, `XMP`, `IPTC`, `ICC`,
  /// `Comment`, `Thumbnail`, `Text` (PNG), `Trailer` (bytes after EOI).
  final List<String> blocks;

  /// Approximate bytes the strip will remove.
  final int metaBytes;

  bool get isEmpty => tagCount == 0 && blocks.isEmpty;
}

/// Image container detected from the first bytes.
String sniffFormat(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'jpeg';
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return 'png';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'webp';
  }
  if (b.length >= 12 &&
      b[4] == 0x66 &&
      b[5] == 0x74 &&
      b[6] == 0x79 &&
      b[7] == 0x70) {
    // 'ftyp' box: HEIF family.
    return 'heic';
  }
  return 'unknown';
}

// ---------------------------------------------------------------------------
// Lossless strip
// ---------------------------------------------------------------------------

/// Remove every metadata block from a JPEG / PNG / WebP file **without
/// re-encoding the pixels**. Returns null for formats this cannot handle
/// (the caller then falls back to a decode → encode path).
///
/// JPEG: drops APP1 (EXIF, XMP), APP2 except ICC_PROFILE, APP3–APP12, APP13
/// (IPTC/Photoshop), APP15 and COM segments; keeps APP0 (JFIF), the ICC
/// profile and APP14 (Adobe colour transform, needed to decode CMYK/YCCK).
/// Anything after EOI (motion-photo MP4 trailers, appended XMP) is cut.
/// PNG: drops tEXt / zTXt / iTXt / eXIf / tIME chunks, cuts after IEND.
/// WebP: drops EXIF / XMP chunks and clears their flags in VP8X.
Uint8List? stripMetadata(Uint8List bytes) {
  switch (sniffFormat(bytes)) {
    case 'jpeg':
      return _stripJpeg(bytes);
    case 'png':
      return _stripPng(bytes);
    case 'webp':
      return _stripWebp(bytes);
    default:
      return null;
  }
}

bool _isIccApp2(Uint8List b, int payloadStart, int payloadLen) {
  const sig = 'ICC_PROFILE';
  if (payloadLen < sig.length + 1) return false;
  for (var i = 0; i < sig.length; i++) {
    if (b[payloadStart + i] != sig.codeUnitAt(i)) return false;
  }
  return b[payloadStart + sig.length] == 0;
}

/// A 32-byte APP1 segment whose TIFF block holds exactly one tag: the
/// orientation. Without it a stripped phone photo would display sideways —
/// the rotation lives in EXIF, not in the pixels — so this is the one piece
/// of metadata a lossless strip must keep. Nothing else is written.
Uint8List _orientationOnlyApp1(int orientation) {
  final tiff = Uint8List(26);
  final d = ByteData.view(tiff.buffer);
  // Little-endian TIFF header, IFD0 at offset 8.
  tiff[0] = 0x49;
  tiff[1] = 0x49;
  d.setUint16(2, 42, Endian.little);
  d.setUint32(4, 8, Endian.little);
  d.setUint16(8, 1, Endian.little); // one entry
  d.setUint16(10, 0x0112, Endian.little); // Orientation
  d.setUint16(12, 3, Endian.little); // SHORT
  d.setUint32(14, 1, Endian.little); // count
  d.setUint16(18, orientation, Endian.little); // value (left-justified)
  d.setUint32(22, 0, Endian.little); // next IFD
  final payload = [...'Exif\x00\x00'.codeUnits, ...tiff];
  final len = payload.length + 2;
  return Uint8List.fromList([0xFF, 0xE1, len >> 8, len & 0xFF, ...payload]);
}

int _orientationOf(Uint8List jpeg) {
  try {
    return img.decodeJpgExif(jpeg)?.imageIfd.orientation ?? 1;
  } catch (_) {
    return 1;
  }
}

Uint8List? _stripJpeg(Uint8List b) {
  final out = BytesBuilder(copy: false);
  out.add(const [0xFF, 0xD8]);
  final orientation = _orientationOf(b);
  if (orientation >= 2 && orientation <= 8) out.add(_orientationOnlyApp1(orientation));
  var p = 2;
  final n = b.length;
  while (p < n) {
    // Skip fill bytes.
    if (b[p] != 0xFF) return null; // corrupt structure; let caller fall back
    while (p < n && b[p] == 0xFF) {
      p++;
    }
    if (p >= n) break;
    final marker = b[p];
    p++;
    if (marker == 0xD9) {
      // EOI: done, drop any trailer.
      out.add(const [0xFF, 0xD9]);
      return out.takeBytes();
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      // Standalone markers (TEM, RSTn) — no length.
      out.add([0xFF, marker]);
      continue;
    }
    if (p + 2 > n) return null;
    final len = (b[p] << 8) | b[p + 1];
    if (len < 2 || p + len > n) return null;
    final payloadStart = p + 2;
    final payloadLen = len - 2;
    final keep = switch (marker) {
      0xE0 => true, // APP0 JFIF
      0xE1 => false, // APP1 EXIF / XMP
      0xE2 => _isIccApp2(b, payloadStart, payloadLen),
      0xEE => true, // APP14 Adobe
      0xFE => false, // COM
      _ when marker >= 0xE3 && marker <= 0xEF => false, // APP3..APP15
      _ => true,
    };
    if (keep) {
      out.add([0xFF, marker]);
      out.add(Uint8List.sublistView(b, p, p + len));
    }
    p += len;
    if (marker == 0xDA) {
      // SOS: entropy-coded data follows until the next real marker. Inside
      // it 0xFF is always followed by 0x00 (stuffing) or 0xD0..0xD7 (RST).
      final start = p;
      while (p < n) {
        if (b[p] == 0xFF && p + 1 < n) {
          final nx = b[p + 1];
          if (nx != 0x00 && !(nx >= 0xD0 && nx <= 0xD7) && nx != 0xFF) {
            break;
          }
        }
        p++;
      }
      out.add(Uint8List.sublistView(b, start, p));
    }
  }
  // No EOI found: return what we have, terminated.
  out.add(const [0xFF, 0xD9]);
  return out.takeBytes();
}

int _be32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

String _fourcc(Uint8List b, int o) => String.fromCharCodes(b, o, o + 4);

const _pngDropChunks = {'tEXt', 'zTXt', 'iTXt', 'eXIf', 'tIME'};

Uint8List? _stripPng(Uint8List b) {
  final out = BytesBuilder(copy: false);
  out.add(Uint8List.sublistView(b, 0, 8));
  var p = 8;
  final n = b.length;
  while (p + 8 <= n) {
    final len = _be32(b, p);
    final type = _fourcc(b, p + 4);
    final total = 12 + len;
    if (len < 0 || p + total > n) return null;
    if (!_pngDropChunks.contains(type)) {
      out.add(Uint8List.sublistView(b, p, p + total));
    }
    p += total;
    if (type == 'IEND') return out.takeBytes();
  }
  return out.takeBytes();
}

int _le32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

void _putLe32(Uint8List b, int o, int v) {
  b[o] = v & 0xFF;
  b[o + 1] = (v >> 8) & 0xFF;
  b[o + 2] = (v >> 16) & 0xFF;
  b[o + 3] = (v >> 24) & 0xFF;
}

Uint8List? _stripWebp(Uint8List b) {
  final n = b.length;
  if (n < 12) return null;
  final chunks = <Uint8List>[];
  var p = 12;
  var dropped = false;
  while (p + 8 <= n) {
    final type = _fourcc(b, p);
    final len = _le32(b, p + 4);
    final padded = len + (len.isOdd ? 1 : 0);
    final end = p + 8 + padded;
    if (len < 0 || p + 8 + len > n) return null;
    final chunk = Uint8List.fromList(
        Uint8List.sublistView(b, p, end > n ? n : end));
    if (type == 'EXIF' || type == 'XMP ') {
      dropped = true;
    } else {
      if (type == 'VP8X' && chunk.length >= 9) {
        // Clear ICC-independent metadata flags: EXIF (bit 3), XMP (bit 2).
        chunk[8] &= ~0x0C;
      }
      chunks.add(chunk);
    }
    p = end;
  }
  if (!dropped) return Uint8List.fromList(b);
  var size = 4;
  for (final c in chunks) {
    size += c.length;
  }
  final out = BytesBuilder(copy: false);
  final header = Uint8List.fromList(Uint8List.sublistView(b, 0, 12));
  _putLe32(header, 4, size);
  out.add(header);
  for (final c in chunks) {
    out.add(c);
  }
  return out.takeBytes();
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

/// Inspect [bytes] and describe the metadata inside. Never throws: a file
/// this cannot parse yields an empty report for its sniffed format.
MetadataReport inspectMetadata(Uint8List bytes) {
  final format = sniffFormat(bytes);
  try {
    switch (format) {
      case 'jpeg':
        return _inspectJpeg(bytes);
      case 'png':
        return _inspectPng(bytes);
      case 'webp':
        return _inspectWebp(bytes);
    }
  } catch (_) {
    // fall through to the empty report
  }
  return MetadataReport(
    format: format,
    entries: const [],
    tagCount: 0,
    hasGps: false,
    latitude: null,
    longitude: null,
    blocks: const [],
    metaBytes: 0,
  );
}

class _Blocks {
  final blocks = <String>[];
  final _sizes = <String, int>{};
  int get bytes => _sizes.values.fold(0, (a, b) => a + b);
  void add(String name, int size) {
    if (!blocks.contains(name)) blocks.add(name);
    _sizes.update(name, (v) => v + size, ifAbsent: () => size);
  }

  void remove(String name) {
    blocks.remove(name);
    _sizes.remove(name);
  }
}

MetadataReport _inspectJpeg(Uint8List b) {
  final blocks = _Blocks();
  img.ExifData? exif;
  var p = 2;
  final n = b.length;
  while (p + 4 <= n && b[p] == 0xFF) {
    final marker = b[p + 1];
    if (marker == 0xD9 || marker == 0xDA) break;
    if (marker == 0xFF) {
      p++;
      continue;
    }
    final len = (b[p + 2] << 8) | b[p + 3];
    if (len < 2 || p + 2 + len > n) break;
    final payload = Uint8List.sublistView(b, p + 4, p + 2 + len);
    switch (marker) {
      case 0xE1:
        if (_startsWith(payload, 'Exif\x00\x00')) {
          blocks.add('EXIF', len);
          exif ??= _readTiff(Uint8List.sublistView(payload, 6));
        } else if (_startsWith(payload, 'http://ns.adobe.com/xap/1.0/')) {
          blocks.add('XMP', len);
        } else {
          blocks.add('APP1', len);
        }
      case 0xE2:
        if (_isIccApp2(b, p + 4, len - 2)) {
          blocks.add('ICC', len);
        } else {
          blocks.add('APP2', len);
        }
      case 0xED:
        blocks.add('IPTC', len);
      case 0xFE:
        blocks.add('Comment', len);
      case 0xE0:
      case 0xEE:
        break;
      default:
        if (marker >= 0xE3 && marker <= 0xEF) blocks.add('APP${marker - 0xE0}', len);
    }
    p += 2 + len;
  }
  // Trailer after EOI (motion photos, appended data).
  final eoi = _lastEoi(b);
  if (eoi >= 0 && eoi + 2 < n) blocks.add('Trailer', n - eoi - 2);
  if (exif?.thumbnailData != null) {
    blocks.add('Thumbnail', exif!.thumbnailData!.length);
  }
  return _reportFromExif('jpeg', exif, blocks, const []);
}

int _lastEoi(Uint8List b) {
  // Scan from the end for FF D9 within the last 64 KB only; an EOI further
  // back than that means a very large trailer, which is still detected.
  for (var i = b.length - 2; i >= 0; i--) {
    if (b[i] == 0xFF && b[i + 1] == 0xD9) return i;
  }
  return -1;
}

bool _startsWith(Uint8List b, String s) {
  if (b.length < s.length) return false;
  for (var i = 0; i < s.length; i++) {
    if (b[i] != s.codeUnitAt(i)) return false;
  }
  return true;
}

img.ExifData? _readTiff(Uint8List tiff) {
  try {
    return img.ExifData.fromInputBuffer(img.InputBuffer(tiff));
  } catch (_) {
    return null;
  }
}

MetadataReport _inspectPng(Uint8List b) {
  final blocks = _Blocks();
  final texts = <MetaEntry>[];
  img.ExifData? exif;
  var p = 8;
  final n = b.length;
  while (p + 8 <= n) {
    final len = _be32(b, p);
    final type = _fourcc(b, p + 4);
    if (len < 0 || p + 12 + len > n) break;
    final data = Uint8List.sublistView(b, p + 8, p + 8 + len);
    switch (type) {
      case 'tEXt':
        blocks.add('Text', len + 12);
        final z = data.indexOf(0);
        if (z > 0) {
          texts.add(MetaEntry('text', latin1.decode(data.sublist(0, z)),
              latin1.decode(data.sublist(z + 1))));
        }
      case 'iTXt':
        blocks.add('Text', len + 12);
        final z = data.indexOf(0);
        if (z > 0) {
          final key = latin1.decode(data.sublist(0, z));
          // compression flag + method + lang\0 + translated\0 + text
          var q = z + 3;
          q = data.indexOf(0, q) + 1;
          q = data.indexOf(0, q) + 1;
          if (q > 0 && q <= data.length && data[z + 1] == 0) {
            texts.add(MetaEntry(
                'text', key, utf8.decode(data.sublist(q), allowMalformed: true)));
          } else {
            texts.add(MetaEntry('text', key, '…'));
          }
        }
      case 'zTXt':
        blocks.add('Text', len + 12);
        final z = data.indexOf(0);
        if (z > 0) {
          texts.add(MetaEntry('text', latin1.decode(data.sublist(0, z)), '…'));
        }
      case 'eXIf':
        blocks.add('EXIF', len + 12);
        exif ??= _readTiff(Uint8List.fromList(data));
      case 'tIME':
        blocks.add('Time', len + 12);
      case 'iCCP':
        blocks.add('ICC', len + 12);
    }
    p += 12 + len;
    if (type == 'IEND') break;
  }
  return _reportFromExif('png', exif, blocks, texts);
}

MetadataReport _inspectWebp(Uint8List b) {
  final blocks = _Blocks();
  img.ExifData? exif;
  var p = 12;
  final n = b.length;
  while (p + 8 <= n) {
    final type = _fourcc(b, p);
    final len = _le32(b, p + 4);
    if (len < 0 || p + 8 + len > n) break;
    final data = Uint8List.sublistView(b, p + 8, p + 8 + len);
    if (type == 'EXIF') {
      blocks.add('EXIF', len + 8);
      var tiff = data;
      if (_startsWith(data, 'Exif\x00\x00')) tiff = Uint8List.sublistView(data, 6);
      exif ??= _readTiff(Uint8List.fromList(tiff));
    } else if (type == 'XMP ') {
      blocks.add('XMP', len + 8);
    } else if (type == 'ICCP') {
      blocks.add('ICC', len + 8);
    }
    p += 8 + len + (len.isOdd ? 1 : 0);
  }
  return _reportFromExif('webp', exif, blocks, const []);
}

// Tags surfaced in the preview, in display order, with their group.
const _curated = <String, String>{
  'Make': 'camera',
  'Model': 'camera',
  'LensModel': 'camera',
  'ExposureTime': 'camera',
  'FNumber': 'camera',
  'ISOSpeedRatings': 'camera',
  'FocalLength': 'camera',
  'DateTimeOriginal': 'time',
  'DateTime': 'time',
  'Software': 'software',
  'Artist': 'author',
  'Copyright': 'author',
  'ImageDescription': 'author',
  'UserComment': 'author',
  'Orientation': 'other',
};

MetadataReport _reportFromExif(String format, img.ExifData? exif, _Blocks blocks,
    List<MetaEntry> extra) {
  final entries = <MetaEntry>[];
  var tagCount = 0;
  double? lat;
  double? lon;
  if (exif != null) {
    for (final dir in exif.directories.values) {
      tagCount += _countTags(dir);
    }
    // An orientation-only EXIF (what our own strip leaves behind) carries
    // nothing personal: do not count it, and do not list an EXIF block.
    if (tagCount == 1 && exif.imageIfd.hasOrientation) {
      tagCount = 0;
      blocks.remove('EXIF');
      exif = null;
    }
  }
  if (exif != null) {
    final named = <String, String>{};
    void collect(img.IfdDirectory dir, Map<int, img.ExifTag> names) {
      for (final id in dir.keys) {
        final tag = names[id];
        if (tag == null) continue;
        final v = dir[id];
        if (v == null) continue;
        named.putIfAbsent(tag.name, () => _valueString(tag.name, v));
      }
      for (final sub in dir.sub.values) {
        collect(sub, img.exifImageTags);
      }
    }
    collect(exif.imageIfd, img.exifImageTags);
    for (final e in _curated.entries) {
      final v = named[e.key];
      if (v != null && v.trim().isNotEmpty) {
        entries.add(MetaEntry(e.value, e.key, v.trim()));
      }
    }
    final gps = exif.gpsIfd;
    if (!gps.isEmpty) {
      lat = _gpsCoord(gps, 0x0002, 0x0001, 'S');
      lon = _gpsCoord(gps, 0x0004, 0x0003, 'W');
      if (lat != null && lon != null) {
        entries.add(MetaEntry('gps', 'GPSPosition',
            '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}'));
      }
      final alt = gps[0x0006];
      if (alt != null) {
        entries.add(MetaEntry('gps', 'GPSAltitude',
            '${alt.toDouble().toStringAsFixed(1)} m'));
      }
      final date = gps[0x001D];
      if (date != null) entries.add(MetaEntry('gps', 'GPSDateStamp', '$date'));
    }
  }
  entries.addAll(extra);
  return MetadataReport(
    format: format,
    entries: entries,
    tagCount: tagCount,
    hasGps: lat != null && lon != null,
    latitude: lat,
    longitude: lon,
    blocks: blocks.blocks,
    metaBytes: blocks.bytes,
  );
}

int _countTags(img.IfdDirectory dir) {
  var n = dir.keys.length;
  for (final s in dir.sub.values) {
    n += _countTags(s);
  }
  return n;
}

String _valueString(String name, img.IfdValue v) {
  switch (name) {
    case 'ExposureTime':
      final d = v.toDouble();
      if (d <= 0) return '$v';
      if (d >= 1) return '${d.toStringAsFixed(1)} s';
      return '1/${(1 / d).round()} s';
    case 'FNumber':
      return 'f/${v.toDouble().toStringAsFixed(1)}';
    case 'FocalLength':
      return '${v.toDouble().toStringAsFixed(1)} mm';
    case 'ISOSpeedRatings':
      return 'ISO ${v.toInt()}';
    case 'UserComment':
      final s = v.toString();
      return s.length > 80 ? '${s.substring(0, 80)}…' : s;
    default:
      final s = v.toString();
      return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}

double? _gpsCoord(img.IfdDirectory gps, int tag, int refTag, String negRef) {
  final v = gps[tag];
  if (v == null || v.length < 3) return null;
  final deg = v.toDouble(0);
  final min = v.toDouble(1);
  final sec = v.toDouble(2);
  if (deg.isNaN || min.isNaN || sec.isNaN) return null;
  var d = deg + min / 60 + sec / 3600;
  final ref = gps[refTag]?.toString().trim().toUpperCase();
  if (ref == negRef) d = -d;
  if (d.abs() > 180) return null;
  return d;
}
