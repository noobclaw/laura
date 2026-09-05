import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'tiling.dart';
import 'upscaler.dart';

/// The on-device Real-ESRGAN engine behind the `photolift/upscale` platform
/// channel — Kotlin (android/.../UpscaleBridge.kt) and Swift
/// (ios/Runner/UpscaleBridge.swift) implement the same contract; this class
/// never branches on the platform.
class NativeUpscaler implements Upscaler {
  NativeUpscaler._();

  static const MethodChannel _method = MethodChannel('photolift/upscale');
  static const EventChannel _events = EventChannel('photolift/upscale/progress');

  static NativeUpscaler? _instance;

  /// Null when the native library is missing on this build/device; the
  /// caller then uses the Dart fallback. Cached after the first probe.
  static Future<NativeUpscaler?> probe() async {
    if (_instance != null) return _instance;
    try {
      final caps = await _method.invokeMapMethod<String, dynamic>('capabilities');
      if (caps?['native'] == true) {
        _instance = NativeUpscaler._();
        return _instance;
      }
      debugPrint('native upscaler reported unavailable: $caps');
    } catch (e) {
      // MissingPluginException in tests / on a build without the bridge.
      debugPrint('native upscaler probe failed: $e');
    }
    return null;
  }

  @override
  bool get isFallback => false;

  @override
  Future<UpscaleResult> run(UpscaleRequest request, {ProgressCallback? onProgress}) async {
    StreamSubscription<dynamic>? sub;
    if (onProgress != null) {
      sub = _events.receiveBroadcastStream().listen((event) {
        if (event is! Map) return;
        if (event['jobId'] != request.jobId) return;
        onProgress(UpscaleProgress(
          done: (event['done'] as num?)?.toInt() ?? 0,
          total: (event['total'] as num?)?.toInt() ?? 1,
          stage: event['stage'] as String? ?? 'infer',
        ));
      }, onError: (Object e) => debugPrint('progress stream error: $e'));
    }
    try {
      final map = await _method.invokeMapMethod<String, dynamic>('upscale', {
        'jobId': request.jobId,
        'inputPath': request.inputPath,
        'outputPath': request.outputPath,
        'scale': request.scale,
        'model': request.denoise.modelKey,
        'useGpu': request.useGpu,
        'tag': request.tag,
        'tagText': request.tagText,
        'maxOutPixels': kMaxOutputPixels,
        'maxOutLongEdge': kMaxOutputLongEdge,
      });
      if (map == null) throw const UpscaleException('inference_failed', 'empty result');
      return UpscaleResult(
        outputPath: map['outputPath'] as String? ?? request.outputPath,
        inWidth: (map['inWidth'] as num?)?.toInt() ?? 0,
        inHeight: (map['inHeight'] as num?)?.toInt() ?? 0,
        outWidth: (map['outWidth'] as num?)?.toInt() ?? 0,
        outHeight: (map['outHeight'] as num?)?.toInt() ?? 0,
        downscaled: map['downscaled'] as bool? ?? false,
        engine: EngineKind.fromWire(map['engine'] as String?),
        elapsedMs: (map['elapsedMs'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') throw const UpscaleCancelled();
      throw UpscaleException(e.code, e.message);
    } on MissingPluginException catch (e) {
      throw UpscaleException('engine_unavailable', e.message);
    } finally {
      await sub?.cancel();
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _method.invokeMethod<void>('cancel');
    } catch (e) {
      debugPrint('cancel failed: $e');
    }
  }
}
