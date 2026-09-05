import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import '../../core/l10n.dart';
import '../models.dart';
import 'image_probe.dart';
import 'metadata.dart';
import 'resize_math.dart';
import 'size_search.dart';
import 'watermark_math.dart';

/// Why a worker gave up. Localised on the UI isolate by [jobFailureMessage]
/// — `tr()` reads the language override, which a fresh isolate does not have.
enum JobFailure { decode, unsupportedFormat, encode, nativeDecode }

class JobError implements Exception {
  JobError(this.failure);
  final JobFailure failure;
  @override
  String toString() => 'JobError(${failure.name})';
}

String jobFailureMessage(JobFailure f) => switch (f) {
      JobFailure.decode => tr(zh: '无法解码这张图片', en: 'Could not decode this image'),
      JobFailure.unsupportedFormat =>
        tr(zh: '该格式暂不支持', en: 'This format is not supported yet'),
      JobFailure.encode => tr(zh: '编码失败', en: 'Encoding failed'),
      JobFailure.nativeDecode =>
        tr(zh: '系统解码失败,可能是不支持的格式', en: 'The system could not decode this file'),
    };

/// Turn any worker exception into a user-facing line.
String describeJobError(Object e) {
  if (e is JobError) return jobFailureMessage(e.failure);
  final s = e.toString();
  if (s.contains('Out of Memory') || s.contains('OutOfMemory')) {
    return tr(zh: '图片太大,内存不足', en: 'Image too large for available memory');
  }
  return '${tr(zh: '处理失败', en: 'Processing failed')}: $s';
}

// ---------------------------------------------------------------------------
// Native path (flutter_image_compress): decode → orient → scale → encode in
// platform code. ~10× faster than pure Dart on a 12 MP photo, reads HEIC,
// writes lossy WebP. Used by compress / resize (shrink) / convert.
// ---------------------------------------------------------------------------

CompressFormat _nativeFormat(ImageFormat f) => switch (f) {
      ImageFormat.png => CompressFormat.png,
      ImageFormat.webp => CompressFormat.webp,
      _ => CompressFormat.jpeg,
    };

/// Re-encode [path] natively. [scale] ≤ 1 shrinks both sides; [fitW]/[fitH]
/// (optional) cap the output box instead. Never upscales.
Future<Uint8List> nativeEncode(
  String path, {
  required ImageFormat format,
  required int quality,
  required bool keepExif,
  double scale = 1.0,
  int? fitW,
  int? fitH,
  int srcW = 0,
  int srcH = 0,
}) async {
  int minW;
  int minH;
  if (fitW != null && fitH != null) {
    minW = fitW;
    minH = fitH;
  } else if (scale < 0.999 && srcW > 0 && srcH > 0) {
    minW = math.max(1, (srcW * scale).round());
    minH = math.max(1, (srcH * scale).round());
  } else {
    // The plugin's box is a *maximum*; a huge box means "keep size".
    minW = 1 << 20;
    minH = 1 << 20;
  }
  final out = await FlutterImageCompress.compressWithFile(
    path,
    minWidth: minW,
    minHeight: minH,
    quality: quality.clamp(1, 100),
    format: _nativeFormat(format),
    keepExif: keepExif,
    autoCorrectionAngle: true,
  );
  if (out == null || out.isEmpty) {
    throw JobError(JobFailure.nativeDecode);
  }
  return out;
}

/// The native encoders drop alpha onto black when writing JPEG. When [src]
/// carries transparency and the target is JPEG, flatten it onto white once
/// (Dart path, near-lossless) and return the flattened file for the native
/// step to work from; otherwise return the source path unchanged.
Future<String> ensureOpaqueSource(SourceImage src, ImageFormat target, String workDir) async {
  if (target != ImageFormat.jpeg) return src.path;
  if (src.format != ImageFormat.png && src.format != ImageFormat.webp) return src.path;
  final probe = await probeFile(src.path);
  if (!probe.info.hasAlpha) return src.path;
  final flat = '$workDir/${src.id}_flat.jpg';
  await runDartJob(DartJobSpec(
    inputPath: src.path,
    outputPath: flat,
    format: ImageFormat.jpeg,
    quality: 97,
    keepMetadata: true,
    edit: const DartEdit(fillWhiteIfAlpha: true),
  ));
  return flat;
}

/// Compress to a target size using the native codec as the probe.
/// Returns the winning bytes plus the search result.
Future<({Uint8List bytes, SizeSearchResult search})> nativeCompressToSize(
  SourceImage src, {
  required ImageFormat format,
  required int targetBytes,
  required bool keepExif,
  String? inputPath,
}) async {
  final input = inputPath ?? src.path;
  // Safety margin from the reference implementation: 2 KB per 5 MB of
  // source, so a file that lands "just under" on the encoder still lands
  // under after container overhead; never below 1 KB.
  final int margin = 2048 * math.max<int>(1, src.bytes ~/ (5 * 1024 * 1024));
  final int target = math.max<int>(1024, targetBytes - margin);
  final lossless = format == ImageFormat.png;
  Uint8List? best;
  Uint8List? last;
  final search = await searchForTargetSize(
    targetBytes: target,
    minQuality: lossless ? 100 : 20,
    maxQuality: lossless ? 100 : 95,
    startQuality: lossless ? 100 : 85,
    probe: (p) async {
      final b = await nativeEncode(input,
          format: format,
          quality: p.quality,
          keepExif: keepExif,
          scale: p.scale,
          srcW: src.width,
          srcH: src.height);
      last = b;
      if (b.length <= target && (best == null || b.length > best!.length)) {
        best = b;
      }
      return b.length;
    },
  );
  final bytes = best ?? last;
  if (bytes == null) throw JobError(JobFailure.encode);
  return (bytes: bytes, search: search);
}

// ---------------------------------------------------------------------------
// Dart path (package:image in an isolate): crop / rotate / flip / watermark /
// alpha fill / explicit resize. One decode + one encode per image.
// ---------------------------------------------------------------------------

/// Pixel-level edits in the upright (orientation-baked) space.
class DartEdit {
  const DartEdit({
    this.cropX,
    this.cropY,
    this.cropW,
    this.cropH,
    this.rotate = 0,
    this.flipH = false,
    this.flipV = false,
    this.resize,
    this.watermark,
    this.fillWhiteIfAlpha = false,
  });

  final int? cropX;
  final int? cropY;
  final int? cropW;
  final int? cropH;

  /// Clockwise degrees: 0 / 90 / 180 / 270. Applied before the crop.
  final int rotate;
  final bool flipH;
  final bool flipV;
  final ResizeSpec? resize;
  final WatermarkJob? watermark;

  /// Composite over white before encoding to JPEG. Reference behaviour is a
  /// black fill; white matches what people expect from a converted logo.
  final bool fillWhiteIfAlpha;

  bool get hasCrop => cropW != null && cropH != null;
}

/// A text sprite pre-rendered on the UI isolate (Flutter text layout is not
/// available in background isolates) plus placement rules.
class WatermarkJob {
  const WatermarkJob({
    required this.rgba,
    required this.width,
    required this.height,
    required this.spec,
  });
  final Uint8List rgba;
  final int width;
  final int height;
  final WatermarkSpec spec;
}

/// Everything an isolate needs to process one file. Plain data only.
class DartJobSpec {
  const DartJobSpec({
    required this.inputPath,
    required this.outputPath,
    required this.format,
    required this.quality,
    required this.keepMetadata,
    required this.edit,
  });
  final String inputPath;

  /// Where to write. For WebP the isolate writes a PNG here and the caller
  /// re-encodes natively (the pure-Dart WebP encoder is lossless only).
  final String outputPath;
  final ImageFormat format;
  final int quality;
  final bool keepMetadata;
  final DartEdit edit;
}

class DartJobOutput {
  const DartJobOutput({required this.width, required this.height, required this.bytes});
  final int width;
  final int height;
  final int bytes;
}

/// Run [spec] on a background isolate.
Future<DartJobOutput> runDartJob(DartJobSpec spec) => Isolate.run(() => _dartWorker(spec));

DartJobOutput _dartWorker(DartJobSpec spec) {
  final bytes = File(spec.inputPath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw JobError(JobFailure.decode);
  }
  // Orientation is baked into the pixels; the tag is dropped so viewers do
  // not rotate a second time (reference: Coil bakes, Orientation never
  // written back).
  var image = img.bakeOrientation(decoded);
  if (image.hasPalette) image = image.convert(numChannels: image.numChannels);
  final e = spec.edit;

  // Rotate and flip first, then crop: the crop rectangle is expressed in the
  // space the user saw on screen (already rotated/flipped).
  if (e.rotate % 360 != 0) {
    image = img.copyRotate(image, angle: e.rotate % 360, interpolation: img.Interpolation.nearest);
  }
  if (e.flipH && e.flipV) {
    image = img.flipHorizontalVertical(image);
  } else if (e.flipH) {
    image = img.flipHorizontal(image);
  } else if (e.flipV) {
    image = img.flipVertical(image);
  }
  if (e.hasCrop) {
    final x = e.cropX!.clamp(0, image.width - 1);
    final y = e.cropY!.clamp(0, image.height - 1);
    final w = e.cropW!.clamp(1, image.width - x);
    final h = e.cropH!.clamp(1, image.height - y);
    if (x != 0 || y != 0 || w != image.width || h != image.height) {
      image = img.copyCrop(image, x: x, y: y, width: w, height: h);
    }
  }
  if (e.resize != null) {
    final t = computeResize(image.width, image.height, e.resize!);
    if (t.width != image.width || t.height != image.height) {
      final shrinking = t.width < image.width;
      image = img.copyResize(image,
          width: t.width,
          height: t.height,
          maintainAspect: false,
          interpolation: shrinking ? img.Interpolation.average : img.Interpolation.cubic);
    }
  }
  if (e.watermark != null) {
    image = _applyWatermark(image, e.watermark!);
  }

  final toJpeg = spec.format == ImageFormat.jpeg;
  if (toJpeg && image.numChannels == 4) {
    // JPEG cannot carry alpha: composite over white.
    final bg = img.Image(width: image.width, height: image.height, numChannels: 3);
    bg.clear(img.ColorRgb8(255, 255, 255));
    img.compositeImage(bg, image);
    image = bg;
  }

  if (spec.keepMetadata) {
    // bakeOrientation already cleared the orientation tag on its copy.
    image.exif = img.ExifData.from(decoded.exif)..imageIfd.orientation = null;
  } else {
    image.exif = img.ExifData();
  }

  Uint8List out;
  switch (spec.format) {
    case ImageFormat.jpeg:
      out = img.encodeJpg(image,
          quality: spec.quality.clamp(1, 100),
          chroma: spec.quality >= 90 ? img.JpegChroma.yuv444 : img.JpegChroma.yuv420);
    case ImageFormat.png:
    case ImageFormat.webp: // PNG intermediate; caller converts natively.
      out = img.encodePng(image, level: 6);
    case ImageFormat.heic:
    case ImageFormat.unknown:
      throw JobError(JobFailure.unsupportedFormat);
  }
  File(spec.outputPath).writeAsBytesSync(out, flush: true);
  return DartJobOutput(width: image.width, height: image.height, bytes: out.length);
}

img.Image _applyWatermark(img.Image image, WatermarkJob wm) {
  if (wm.width <= 0 || wm.height <= 0) return image;
  var sprite = img.Image.fromBytes(
    width: wm.width,
    height: wm.height,
    bytes: wm.rgba.buffer,
    bytesOffset: wm.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  // Opacity: scale the alpha channel once, on the sprite.
  final a = wm.spec.opacity.clamp(0.0, 1.0);
  if (a < 0.999) {
    for (final p in sprite) {
      p.a = (p.a * a).round();
    }
  }
  if (image.numChannels < 3) image = image.convert(numChannels: 3);
  final short = math.min(image.width, image.height);
  final margin = watermarkMarginPx(short, wm.spec.marginPercent);

  if (wm.spec.tiled) {
    if (wm.spec.tileAngleDeg % 360 != 0) {
      sprite = img.copyRotate(sprite, angle: wm.spec.tileAngleDeg, interpolation: img.Interpolation.linear);
    }
    for (final pos in tilePositions(
        w: image.width, h: image.height, spriteW: sprite.width, spriteH: sprite.height)) {
      _blit(image, sprite, pos.x, pos.y);
    }
  } else {
    final o = anchorOffset(
      w: image.width,
      h: image.height,
      spriteW: sprite.width,
      spriteH: sprite.height,
      margin: margin,
      anchor: wm.spec.anchor,
    );
    _blit(image, sprite, o.x, o.y);
  }
  return image;
}

/// Alpha-composite [src] onto [dst] at (dx, dy), clipping at the edges.
void _blit(img.Image dst, img.Image src, int dx, int dy) {
  final sx0 = dx < 0 ? -dx : 0;
  final sy0 = dy < 0 ? -dy : 0;
  final x0 = math.max(0, dx);
  final y0 = math.max(0, dy);
  final w = math.min(src.width - sx0, dst.width - x0);
  final h = math.min(src.height - sy0, dst.height - y0);
  if (w <= 0 || h <= 0) return;
  img.compositeImage(dst, src,
      dstX: x0, dstY: y0, dstW: w, dstH: h, srcX: sx0, srcY: sy0, srcW: w, srcH: h);
}

// ---------------------------------------------------------------------------
// Metadata strip: byte-level, no re-encode. Runs in an isolate.
// ---------------------------------------------------------------------------

Future<DartJobOutput> runStripJob(String inputPath, String outputPath) =>
    Isolate.run(() {
      final bytes = File(inputPath).readAsBytesSync();
      final out = stripMetadata(bytes);
      if (out == null) {
        throw JobError(JobFailure.unsupportedFormat);
      }
      File(outputPath).writeAsBytesSync(out, flush: true);
      final info = probeImage(out);
      return DartJobOutput(width: info.width, height: info.height, bytes: out.length);
    });

/// Inspect metadata off the UI isolate.
Future<MetadataReport> inspectFile(String path) =>
    Isolate.run(() => inspectMetadata(File(path).readAsBytesSync()));

/// Probe a file's header off the UI isolate.
Future<({ProbeInfo info, int bytes})> probeFile(String path) => Isolate.run(() {
      final b = File(path).readAsBytesSync();
      return (info: probeImage(b), bytes: b.length);
    });

/// Convert a WebP-destined PNG intermediate into a real lossy WebP.
Future<Uint8List> pngToWebp(String pngPath, int quality) async {
  try {
    final out = await FlutterImageCompress.compressWithFile(
      pngPath,
      minWidth: 1 << 20,
      minHeight: 1 << 20,
      quality: quality.clamp(1, 100),
      format: CompressFormat.webp,
      keepExif: false,
    );
    if (out != null && out.isNotEmpty) return out;
  } catch (e) {
    debugPrint('native webp failed, falling back to lossless: $e');
  }
  // Lossless fallback so the user still gets a valid WebP.
  return Isolate.run(() {
    final im = img.decodePng(File(pngPath).readAsBytesSync());
    if (im == null) throw JobError(JobFailure.encode);
    return img.encodeWebP(im);
  });
}
