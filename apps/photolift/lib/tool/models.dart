import '../core/l10n.dart';

/// Denoise strength. Each level is a separate set of Real-ESRGAN weights
/// (see pubspec assets): dn0 = plain general-x4v3, dn1 = the "wdn"
/// (with-denoise) weights, dn05 = a 50/50 weight-space blend.
enum DenoiseLevel {
  off('general-x4v3-dn0'),
  light('general-x4v3-dn05'),
  strong('general-x4v3-dn1');

  const DenoiseLevel(this.modelKey);

  /// Asset base name under assets/models/.
  final String modelKey;

  String get label => switch (this) {
        DenoiseLevel.off => tr(zh: '关', en: 'Off'),
        DenoiseLevel.light => tr(zh: '轻度', en: 'Light'),
        DenoiseLevel.strong => tr(zh: '强', en: 'Strong'),
      };

  static DenoiseLevel fromIndex(int? i) =>
      DenoiseLevel.values[(i ?? 1).clamp(0, DenoiseLevel.values.length - 1)];
}

/// Which code path produced a result.
enum EngineKind {
  ncnnGpu('ncnn-gpu'),
  ncnnCpu('ncnn-cpu'),
  dartFallback('dart-fallback');

  const EngineKind(this.wire);
  final String wire;

  static EngineKind fromWire(String? s) => EngineKind.values.firstWhere(
        (e) => e.wire == s,
        orElse: () => EngineKind.dartFallback,
      );

  bool get isAi => this != EngineKind.dartFallback;

  String get label => switch (this) {
        EngineKind.ncnnGpu => tr(zh: 'AI · GPU', en: 'AI · GPU'),
        EngineKind.ncnnCpu => tr(zh: 'AI · CPU', en: 'AI · CPU'),
        EngineKind.dartFallback => tr(zh: '基础放大', en: 'Basic resample'),
      };
}

/// One processed photo in the local history. Both files live in the app's
/// private `lifted/` folder: the source copy (so the before/after view keeps
/// working after the picker cache is cleared) and the JPEG result.
class LiftRecord {
  LiftRecord({
    required this.id,
    required this.sourceName,
    required this.outputName,
    required this.scale,
    required this.denoise,
    required this.createdAt,
    required this.inWidth,
    required this.inHeight,
    required this.outWidth,
    required this.outHeight,
    required this.engine,
    required this.elapsedMs,
    required this.tagged,
  });

  final String id;
  final String sourceName;
  final String outputName;
  final int scale;
  final DenoiseLevel denoise;
  final DateTime createdAt;
  final int inWidth;
  final int inHeight;
  final int outWidth;
  final int outHeight;
  final EngineKind engine;
  final int elapsedMs;
  /// Free-tier corner tag was burned into the output.
  final bool tagged;

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceName': sourceName,
        'outputName': outputName,
        'scale': scale,
        'denoise': denoise.index,
        'createdAt': createdAt.toIso8601String(),
        'inWidth': inWidth,
        'inHeight': inHeight,
        'outWidth': outWidth,
        'outHeight': outHeight,
        'engine': engine.wire,
        'elapsedMs': elapsedMs,
        'tagged': tagged,
      };

  static LiftRecord? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final src = j['sourceName'];
    final out = j['outputName'];
    if (id is! String || src is! String || out is! String) return null;
    return LiftRecord(
      id: id,
      sourceName: src,
      outputName: out,
      scale: (j['scale'] as num?)?.toInt() ?? 2,
      denoise: DenoiseLevel.fromIndex((j['denoise'] as num?)?.toInt()),
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      inWidth: (j['inWidth'] as num?)?.toInt() ?? 0,
      inHeight: (j['inHeight'] as num?)?.toInt() ?? 0,
      outWidth: (j['outWidth'] as num?)?.toInt() ?? 0,
      outHeight: (j['outHeight'] as num?)?.toInt() ?? 0,
      engine: EngineKind.fromWire(j['engine'] as String?),
      elapsedMs: (j['elapsedMs'] as num?)?.toInt() ?? 0,
      tagged: j['tagged'] as bool? ?? false,
    );
  }
}
