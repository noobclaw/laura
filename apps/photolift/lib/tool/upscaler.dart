import 'models.dart';

/// One upscale job as the engines see it. Paths are absolute; the output is
/// always a JPEG written atomically (tmp + rename) by the engine.
class UpscaleRequest {
  const UpscaleRequest({
    required this.jobId,
    required this.inputPath,
    required this.outputPath,
    required this.scale,
    required this.denoise,
    required this.useGpu,
    required this.tag,
    this.tagText = 'PhotoLift',
  });

  final String jobId;
  final String inputPath;
  final String outputPath;
  /// 2 or 4.
  final int scale;
  final DenoiseLevel denoise;
  /// Android only; iOS is CPU-only for now, the fallback ignores it.
  final bool useGpu;
  /// Burn the free-tier corner tag into the output.
  final bool tag;
  final String tagText;
}

class UpscaleResult {
  const UpscaleResult({
    required this.outputPath,
    required this.inWidth,
    required this.inHeight,
    required this.outWidth,
    required this.outHeight,
    required this.downscaled,
    required this.engine,
    required this.elapsedMs,
  });

  final String outputPath;
  final int inWidth;
  final int inHeight;
  final int outWidth;
  final int outHeight;
  /// The source was larger than the caps and was shrunk before upscaling.
  final bool downscaled;
  final EngineKind engine;
  final int elapsedMs;
}

class UpscaleProgress {
  const UpscaleProgress({required this.done, required this.total, required this.stage});
  final int done;
  final int total;
  /// decode | infer | encode
  final String stage;

  double get fraction => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
}

class UpscaleCancelled implements Exception {
  const UpscaleCancelled();
  @override
  String toString() => 'UpscaleCancelled';
}

/// A failure with a stable [code] (see the bridge contracts) so the UI can
/// explain it: engine_unavailable | engine_load_failed | decode_failed |
/// too_large | inference_failed | write_failed | busy | bad_args.
class UpscaleException implements Exception {
  const UpscaleException(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  String toString() => 'UpscaleException($code${message == null ? '' : ': $message'})';
}

typedef ProgressCallback = void Function(UpscaleProgress progress);

abstract class Upscaler {
  /// True for the pure-Dart resampler that stands in when the native AI
  /// engine is unavailable. Results are labelled so the user is never told
  /// a cubic resize was "AI".
  bool get isFallback;

  Future<UpscaleResult> run(UpscaleRequest request, {ProgressCallback? onProgress});

  /// Best-effort abort of the running job; `run` then throws [UpscaleCancelled].
  Future<void> cancel();
}
