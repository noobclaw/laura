import 'models.dart';

/// Time estimate for a job, in seconds per megapixel of *output*, learned
/// per engine from finished runs (exponential moving average) and seeded
/// with conservative defaults for the first run. Pure and persisted by the
/// store as a small map.
class EtaModel {
  EtaModel([Map<String, double>? rates])
      : _rates = {..._defaults, ...?rates};

  /// Seconds per output megapixel before any measurement. GPU figures are
  /// mid-range Adreno/Mali; CPU is a 4-big-core phone; the Dart fallback is
  /// single-isolate cubic resampling.
  static const Map<String, double> _defaults = {
    'ncnn-gpu': 1.6,
    'ncnn-cpu': 12.0,
    'dart-fallback': 2.5,
  };

  final Map<String, double> _rates;

  Map<String, double> toJson() => Map.of(_rates);

  double rateFor(EngineKind engine) =>
      _rates[engine.wire] ?? _defaults[engine.wire] ?? 10.0;

  /// The pixel count a run is billed on. The ncnn network is a fixed 4x
  /// model - a 2x job runs the same 4x inference and only box-filters each
  /// tile down - so its cost is the 4x-equivalent output, not the 2x output.
  /// The Dart fallback really does scale with what it writes.
  static int billablePixels(int outPixels, int scale, EngineKind engine) {
    if (!engine.isAi || scale <= 0) return outPixels;
    final factor = 16 ~/ (scale * scale); // 4 for 2x, 1 for 4x
    return outPixels * (factor < 1 ? 1 : factor);
  }

  /// Estimated seconds for an output of [outPixels] pixels at [scale].
  double estimateSeconds(int outPixels, EngineKind engine, {int scale = 4}) {
    if (outPixels <= 0) return 0;
    final px = billablePixels(outPixels, scale, engine);
    // + fixed cost: decode, model load, JPEG encode.
    return 1.5 + px / 1e6 * rateFor(engine);
  }

  /// Fold a finished run into the estimate (EMA, weight 0.4 on the new sample).
  void record(int outPixels, EngineKind engine, int elapsedMs, {int scale = 4}) {
    if (outPixels <= 0 || elapsedMs <= 0) return;
    final px = billablePixels(outPixels, scale, engine);
    final sample = (elapsedMs / 1000 - 1.5).clamp(0.05, double.infinity) / (px / 1e6);
    if (!sample.isFinite) return;
    final old = rateFor(engine);
    _rates[engine.wire] = old * 0.6 + sample * 0.4;
  }
}

/// Human-friendly duration for estimates and results ("约 12 秒", "~2 min").
String formatEta(double seconds, {required bool zh}) {
  if (!seconds.isFinite) return zh ? '计算中…' : 'estimating…';
  if (seconds < 1) return zh ? '不到 1 秒' : 'under 1 s';
  if (seconds < 60) {
    final s = seconds.round();
    return zh ? '约 $s 秒' : '~$s s';
  }
  final m = (seconds / 60).floor();
  final s = (seconds - m * 60).round();
  if (m >= 10 || s == 0) return zh ? '约 $m 分钟' : '~$m min';
  return zh ? '约 $m 分 $s 秒' : '~${m}m ${s}s';
}
