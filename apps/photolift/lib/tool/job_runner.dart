import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/l10n.dart';
import 'fallback_upscaler.dart';
import 'media.dart';
import 'models.dart';
import 'native_upscaler.dart';
import 'store.dart';
import 'upscaler.dart';

/// Runs one photo through the engine and books the result into the store:
/// copies the source into the private library, picks the engine (native AI
/// first, Dart resampler as the labelled fallback), consumes the free-tier
/// quota only on success, and records timing for the next estimate.
class LiftJobRunner {
  LiftJobRunner(this.store);

  final PhotoLiftStore store;
  Upscaler? _engine;

  Future<Upscaler> engine() async {
    final existing = _engine;
    if (existing != null) return existing;
    final native = await NativeUpscaler.probe();
    final e = native ?? DartFallbackUpscaler();
    if (native == null) debugPrint('PhotoLift: native engine unavailable, using Dart FALLBACK');
    _engine = e;
    return e;
  }

  /// Throws [UpscaleCancelled] or [UpscaleException]; the partial source copy
  /// is removed in both cases.
  Future<LiftRecord> run({
    required PickedPhoto photo,
    required int scale,
    required DenoiseLevel denoise,
    ProgressCallback? onProgress,
  }) async {
    final id = store.newId();
    final String srcName;
    try {
      srcName = await store.importSource(photo.path, id);
    } on FileSystemException catch (e) {
      throw UpscaleException('write_failed', e.message);
    }
    final outName = store.outputNameFor(id);
    final eng = await engine();
    final tag = !store.pro;
    final req = UpscaleRequest(
      jobId: id,
      inputPath: store.pathFor(srcName),
      outputPath: store.pathFor(outName),
      scale: scale,
      denoise: denoise,
      useGpu: store.useGpu,
      tag: tag,
    );
    try {
      final res = await eng.run(req, onProgress: onProgress);
      final rec = LiftRecord(
        id: id,
        sourceName: srcName,
        outputName: outName,
        scale: scale,
        denoise: denoise,
        createdAt: DateTime.now(),
        inWidth: res.inWidth,
        inHeight: res.inHeight,
        outWidth: res.outWidth,
        outHeight: res.outHeight,
        engine: res.engine,
        elapsedMs: res.elapsedMs,
        tagged: tag,
      );
      store.consumeQuota();
      store.addRecord(rec);
      store.recordEta(rec);
      return rec;
    } catch (_) {
      for (final p in [store.pathFor(srcName), store.pathFor(outName), '${store.pathFor(outName)}.tmp']) {
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (e) {
          debugPrint('cleanup $p failed: $e');
        }
      }
      rethrow;
    }
  }

  Future<void> cancel() async => _engine?.cancel();
}

/// User-facing explanation for an engine error code.
String describeUpscaleError(Object error) {
  if (error is UpscaleException) {
    return switch (error.code) {
      'engine_unavailable' || 'engine_load_failed' => tr(
          zh: 'AI 引擎无法启动。请重启应用再试;如果一直失败,可能是这台设备不受支持。',
          en: 'The AI engine could not start. Restart the app and try again; if it keeps failing this device may be unsupported.'),
      'decode_failed' => tr(
          zh: '无法读取这张图片,可能是格式不支持或文件已损坏。',
          en: 'This image could not be read — unsupported format or damaged file.'),
      'too_large' => tr(
          zh: '内存不足,处理不了这么大的图。请关闭其它应用或换一张小一点的照片。',
          en: 'Not enough memory for an image this large. Close other apps or pick a smaller photo.'),
      'write_failed' => tr(
          zh: '结果写入失败,请检查手机存储空间。',
          en: 'Could not write the result — check free storage on the phone.'),
      'busy' => tr(zh: '上一张还在处理中。', en: 'The previous photo is still processing.'),
      _ => Platform.isAndroid
          ? tr(
              zh: '处理失败(${error.code})。请再试一次;若仍失败可在设置里关闭 GPU 加速后重试。',
              en: 'Processing failed (${error.code}). Try again; if it keeps failing, turn off GPU acceleration in Settings.')
          : tr(
              zh: '处理失败(${error.code})。请再试一次。',
              en: 'Processing failed (${error.code}). Please try again.'),
    };
  }
  if (error is MediaException) {
    return switch (error.code) {
      'picker_unavailable' => tr(
          zh: '打不开系统相册选择器。', en: 'The system photo picker could not be opened.'),
      'copy_failed' => tr(
          zh: '读取所选照片失败,请换一张试试。', en: 'Could not read the chosen photo — try another one.'),
      'permission_denied' => tr(
          zh: '没有写入相册的权限。', en: 'Permission to add to Photos was denied.'),
      _ => tr(zh: '保存失败(${error.code})。', en: 'Save failed (${error.code}).'),
    };
  }
  return tr(zh: '出错了:$error', en: 'Something went wrong: $error');
}
