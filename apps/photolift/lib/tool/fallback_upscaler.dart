// FALLBACK ENGINE — not AI.
//
// Used only when the native ncnn engine is unavailable (a build without the
// native step, or an unsupported ABI). Cubic resampling + a mild unsharp
// mask, plus a Gaussian pre-blur for "denoise". Results are labelled
// [EngineKind.dartFallback] end to end so the UI never calls this "AI".
// PLAN.md「技术选型」explains when it is expected to be switched off.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'models.dart';
import 'tiling.dart';
import 'upscaler.dart';

class DartFallbackUpscaler implements Upscaler {
  bool _cancelled = false;

  @override
  bool get isFallback => true;

  @override
  Future<UpscaleResult> run(UpscaleRequest request, {ProgressCallback? onProgress}) async {
    _cancelled = false;
    final t0 = DateTime.now();
    onProgress?.call(const UpscaleProgress(done: 0, total: 3, stage: 'decode'));
    final bytes = await File(request.inputPath).readAsBytes();
    if (_cancelled) throw const UpscaleCancelled();
    onProgress?.call(const UpscaleProgress(done: 1, total: 3, stage: 'infer'));
    final args = FallbackArgs(
      bytes: bytes,
      scale: request.scale,
      denoise: request.denoise,
      tag: request.tag,
      tagText: request.tagText,
    );
    final out = await Isolate.run(() => fallbackProcess(args));
    if (_cancelled) throw const UpscaleCancelled();
    onProgress?.call(const UpscaleProgress(done: 2, total: 3, stage: 'encode'));
    final file = File(request.outputPath);
    await file.parent.create(recursive: true);
    final tmp = File('${request.outputPath}.tmp');
    try {
      await tmp.writeAsBytes(out.jpeg, flush: true);
      await tmp.rename(request.outputPath);
    } on FileSystemException catch (e) {
      throw UpscaleException('write_failed', e.message);
    }
    onProgress?.call(const UpscaleProgress(done: 3, total: 3, stage: 'encode'));
    return UpscaleResult(
      outputPath: request.outputPath,
      inWidth: out.inWidth,
      inHeight: out.inHeight,
      outWidth: out.outWidth,
      outHeight: out.outHeight,
      downscaled: out.downscaled,
      engine: EngineKind.dartFallback,
      elapsedMs: DateTime.now().difference(t0).inMilliseconds,
    );
  }

  @override
  Future<void> cancel() async {
    // The isolate cannot be interrupted mid-resize; the result is discarded.
    _cancelled = true;
  }
}

class FallbackArgs {
  const FallbackArgs({
    required this.bytes,
    required this.scale,
    required this.denoise,
    required this.tag,
    required this.tagText,
  });
  final Uint8List bytes;
  final int scale;
  final DenoiseLevel denoise;
  final bool tag;
  final String tagText;
}

class FallbackOutput {
  const FallbackOutput({
    required this.jpeg,
    required this.inWidth,
    required this.inHeight,
    required this.outWidth,
    required this.outHeight,
    required this.downscaled,
  });
  final Uint8List jpeg;
  final int inWidth;
  final int inHeight;
  final int outWidth;
  final int outHeight;
  final bool downscaled;
}

/// Pure function (runs in an isolate; also exercised by the unit tests).
FallbackOutput fallbackProcess(FallbackArgs a) {
  img.Image? src;
  try {
    src = img.decodeImage(a.bytes);
  } catch (e) {
    // The decoders throw on truncated files rather than returning null.
    throw UpscaleException('decode_failed', '$e');
  }
  if (src == null) throw const UpscaleException('decode_failed', 'not an image');
  src = img.bakeOrientation(src);
  if (src.numChannels != 3) src = src.convert(numChannels: 3);

  final fit = fitInput(src.width, src.height, a.scale);
  final downscaled = fit.width != src.width || fit.height != src.height;
  if (downscaled) {
    src = img.copyResize(src,
        width: fit.width, height: fit.height, interpolation: img.Interpolation.cubic);
  }
  switch (a.denoise) {
    case DenoiseLevel.off:
      break;
    case DenoiseLevel.light:
      src = img.gaussianBlur(src, radius: 1);
    case DenoiseLevel.strong:
      src = img.gaussianBlur(src, radius: 2);
  }

  var out = img.copyResize(src,
      width: src.width * a.scale,
      height: src.height * a.scale,
      interpolation: img.Interpolation.cubic);
  // Mild unsharp mask so the cubic result does not read as plain blur.
  out = img.convolution(out,
      filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0], div: 1, amount: 0.35);

  if (a.tag) _drawTag(out, a.tagText);

  return FallbackOutput(
    jpeg: img.encodeJpg(out, quality: 92),
    inWidth: src.width,
    inHeight: src.height,
    outWidth: out.width,
    outHeight: out.height,
    downscaled: downscaled,
  );
}

void _drawTag(img.Image image, String text) {
  final font = image.width >= 2400 ? img.arial48 : img.arial24;
  final textW = text.length * (font.size * 0.6);
  final textH = font.size.toDouble();
  final padX = font.size * 0.5;
  final padY = font.size * 0.3;
  final margin = (image.width * 0.02).clamp(6, 200).toDouble();
  final x2 = (image.width - margin).round();
  final y2 = (image.height - margin).round();
  final x1 = (x2 - textW - padX * 2).round();
  final y1 = (y2 - textH - padY * 2).round();
  img.fillRect(image,
      x1: x1, y1: y1, x2: x2, y2: y2,
      color: img.ColorRgba8(0, 0, 0, 140), radius: font.size * 0.5);
  img.drawString(image, text,
      font: font, x: (x1 + padX).round(), y: (y1 + padY).round(),
      color: img.ColorRgb8(255, 255, 255));
}
