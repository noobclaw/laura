import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models.dart';
import 'metadata.dart';

/// Header-only facts about an encoded image. Never decodes pixels.
class ProbeInfo {
  const ProbeInfo({
    required this.format,
    required this.width,
    required this.height,
    required this.hasAlpha,
    this.orientation = 1,
  });
  final ImageFormat format;
  final int width;
  final int height;

  /// True when the container declares an alpha channel (PNG colour type
  /// 4/6 or a tRNS chunk, WebP VP8X alpha flag / VP8L). JPEG never has one.
  final bool hasAlpha;

  /// EXIF orientation (1..8) for JPEG, 1 otherwise.
  final int orientation;
}

ImageFormat formatFromSniff(String s) => switch (s) {
      'jpeg' => ImageFormat.jpeg,
      'png' => ImageFormat.png,
      'webp' => ImageFormat.webp,
      'heic' => ImageFormat.heic,
      _ => ImageFormat.unknown,
    };

/// Probe [bytes]. Dimensions come from the container header; for containers
/// the pure-Dart decoders do not know (HEIC) they are 0 and the caller must
/// convert first. Safe to call inside an isolate.
ProbeInfo probeImage(Uint8List bytes) {
  final format = formatFromSniff(sniffFormat(bytes));
  var w = 0;
  var h = 0;
  var alpha = false;
  var orientation = 1;
  try {
    switch (format) {
      case ImageFormat.jpeg:
        final info = img.JpegDecoder().startDecode(bytes);
        w = info?.width ?? 0;
        h = info?.height ?? 0;
        // Report the upright size: an EXIF orientation of 5..8 means the
        // stored pixels are rotated 90°, and every tool works upright.
        final o = _jpegOrientation(bytes);
        orientation = o.clamp(1, 8);
        if (o >= 5 && o <= 8) {
          final t = w;
          w = h;
          h = t;
        }
      case ImageFormat.png:
        final info = img.PngDecoder().startDecode(bytes);
        w = info?.width ?? 0;
        h = info?.height ?? 0;
        alpha = _pngHasAlpha(bytes);
      case ImageFormat.webp:
        final info = img.WebPDecoder().startDecode(bytes);
        w = info?.width ?? 0;
        h = info?.height ?? 0;
        alpha = info?.hasAlpha ?? false;
      case ImageFormat.heic:
      case ImageFormat.unknown:
        final dec = img.findDecoderForData(bytes);
        final info = dec?.startDecode(bytes);
        w = info?.width ?? 0;
        h = info?.height ?? 0;
    }
  } catch (_) {
    // A truncated header is reported as 0×0; the pipeline rejects it later
    // with a readable error instead of crashing here.
  }
  return ProbeInfo(format: format, width: w, height: h, hasAlpha: alpha, orientation: orientation);
}

int _jpegOrientation(Uint8List b) {
  try {
    return img.decodeJpgExif(b)?.imageIfd.orientation ?? 1;
  } catch (_) {
    return 1;
  }
}

bool _pngHasAlpha(Uint8List b) {
  // IHDR is always the first chunk: 8 sig + 4 len + 4 type + 13 data.
  if (b.length < 33) return false;
  final colorType = b[25];
  if (colorType == 4 || colorType == 6) return true;
  // Scan chunk headers for tRNS before IDAT.
  var p = 8;
  while (p + 8 <= b.length) {
    final len = (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];
    final type = String.fromCharCodes(b, p + 4, p + 8);
    if (type == 'tRNS') return true;
    if (type == 'IDAT' || type == 'IEND') return false;
    if (len < 0) return false;
    p += 12 + len;
  }
  return false;
}
