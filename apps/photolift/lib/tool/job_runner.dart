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
          en: 'The AI engine could not start. Restart the app and try again; if it keeps failing this device may be unsupported.', zht: 'AI 引擎無法啟動。請重新啟動應用再試；如果一直失敗，可能是這台裝置不受支援。', ja: 'AIエンジンを起動できませんでした。アプリを再起動してお試しください。何度も失敗する場合、この端末は非対応の可能性があります。', es: 'No se pudo iniciar el motor de IA. Reinicia la app e inténtalo de nuevo; si sigue fallando, puede que este dispositivo no sea compatible.', pt: 'Não foi possível iniciar o motor de IA. Reinicie o app e tente de novo; se continuar falhando, este aparelho pode não ser compatível.', de: 'Die KI-Engine konnte nicht starten. Starte die App neu und versuche es erneut; schlägt es weiter fehl, wird dieses Gerät eventuell nicht unterstützt.', fr: 'Le moteur d\'IA n\'a pas pu démarrer. Redémarrez l\'app et réessayez ; si l\'échec persiste, cet appareil n\'est peut-être pas pris en charge.'),
      'decode_failed' => tr(
          zh: '无法读取这张图片,可能是格式不支持或文件已损坏。',
          en: 'This image could not be read — unsupported format or damaged file.', zht: '無法讀取這張圖片，可能是格式不支援或檔案已損壞。', ja: 'この画像を読み込めませんでした（非対応の形式か、ファイルが壊れています）。', es: 'No se pudo leer esta imagen: formato no compatible o archivo dañado.', pt: 'Não foi possível ler esta imagem — formato não suportado ou arquivo danificado.', de: 'Dieses Bild konnte nicht gelesen werden – Format nicht unterstützt oder Datei beschädigt.', fr: 'Impossible de lire cette image — format non pris en charge ou fichier endommagé.'),
      'too_large' => tr(
          zh: '内存不足,处理不了这么大的图。请关闭其它应用或换一张小一点的照片。',
          en: 'Not enough memory for an image this large. Close other apps or pick a smaller photo.', zht: '記憶體不足，處理不了這麼大的圖。請關閉其他應用或換一張小一點的照片。', ja: 'メモリが足りず、この大きさの画像は処理できません。他のアプリを閉じるか、小さめの写真を選んでください。', es: 'No hay memoria suficiente para una imagen tan grande. Cierra otras apps o elige una foto más pequeña.', pt: 'Memória insuficiente para uma imagem tão grande. Feche outros apps ou escolha uma foto menor.', de: 'Nicht genug Speicher für ein so großes Bild. Schließe andere Apps oder wähle ein kleineres Foto.', fr: 'Mémoire insuffisante pour une image aussi grande. Fermez d\'autres apps ou choisissez une photo plus petite.'),
      'write_failed' => tr(
          zh: '结果写入失败,请检查手机存储空间。',
          en: 'Could not write the result — check free storage on the phone.', zht: '結果寫入失敗，請檢查手機儲存空間。', ja: '結果を書き込めませんでした。端末の空き容量を確認してください。', es: 'No se pudo guardar el resultado: revisa el espacio libre del teléfono.', pt: 'Não foi possível gravar o resultado — verifique o espaço livre do celular.', de: 'Ergebnis konnte nicht geschrieben werden – prüfe den freien Speicher.', fr: 'Impossible d\'écrire le résultat — vérifiez l\'espace libre du téléphone.'),
      'busy' => tr(zh: '上一张还在处理中。', en: 'The previous photo is still processing.', zht: '上一張還在處理中。', ja: '前の写真をまだ処理中です。', es: 'La foto anterior aún se está procesando.', pt: 'A foto anterior ainda está sendo processada.', de: 'Das vorige Foto wird noch verarbeitet.', fr: 'La photo précédente est encore en cours de traitement.'),
      _ => Platform.isAndroid
          ? tr(
              zh: '处理失败(${error.code})。请再试一次;若仍失败可在设置里关闭 GPU 加速后重试。',
              en: 'Processing failed (${error.code}). Try again; if it keeps failing, turn off GPU acceleration in Settings.', zht: '處理失敗（${error.code}）。請再試一次；若仍失敗可在設定裡關閉 GPU 加速後重試。', ja: '処理に失敗しました（${error.code}）。もう一度お試しください。失敗が続く場合は設定で GPU アクセラレーションをオフにしてください。', es: 'El procesamiento falló (${error.code}). Inténtalo de nuevo; si sigue fallando, desactiva la aceleración GPU en Ajustes.', pt: 'O processamento falhou (${error.code}). Tente de novo; se continuar falhando, desative a aceleração por GPU em Ajustes.', de: 'Verarbeitung fehlgeschlagen (${error.code}). Versuche es erneut; schlägt es weiter fehl, schalte die GPU-Beschleunigung in den Einstellungen aus.', fr: 'Le traitement a échoué (${error.code}). Réessayez ; si l\'échec persiste, désactivez l\'accélération GPU dans Réglages.')
          : tr(
              zh: '处理失败(${error.code})。请再试一次。',
              en: 'Processing failed (${error.code}). Please try again.', zht: '處理失敗（${error.code}）。請再試一次。', ja: '処理に失敗しました（${error.code}）。もう一度お試しください。', es: 'El procesamiento falló (${error.code}). Inténtalo de nuevo.', pt: 'O processamento falhou (${error.code}). Tente novamente.', de: 'Verarbeitung fehlgeschlagen (${error.code}). Bitte erneut versuchen.', fr: 'Le traitement a échoué (${error.code}). Veuillez réessayer.'),
    };
  }
  if (error is MediaException) {
    return switch (error.code) {
      'picker_unavailable' => tr(
          zh: '打不开系统相册选择器。', en: 'The system photo picker could not be opened.', zht: '無法開啟系統相簿選擇器。', ja: '写真ピッカーを開けませんでした。', es: 'No se pudo abrir el selector de fotos.', pt: 'Não foi possível abrir o seletor de fotos.', de: 'Die Fotoauswahl konnte nicht geöffnet werden.', fr: 'Impossible d\'ouvrir le sélecteur de photos.'),
      'copy_failed' => tr(
          zh: '读取所选照片失败,请换一张试试。', en: 'Could not read the chosen photo — try another one.', zht: '讀取所選照片失敗，請換一張試試。', ja: '選んだ写真を読み込めませんでした。別の写真をお試しください。', es: 'No se pudo leer la foto elegida: prueba con otra.', pt: 'Não foi possível ler a foto escolhida — tente outra.', de: 'Das gewählte Foto konnte nicht gelesen werden – probier ein anderes.', fr: 'Impossible de lire la photo choisie — essayez-en une autre.'),
      'permission_denied' => tr(
          zh: '没有写入相册的权限。', en: 'Permission to add to Photos was denied.', zht: '沒有寫入相簿的權限。', ja: '写真への追加が許可されていません。', es: 'Se denegó el permiso para añadir a Fotos.', pt: 'A permissão para adicionar a Fotos foi negada.', de: 'Die Berechtigung zum Hinzufügen zu Fotos wurde verweigert.', fr: 'L\'autorisation d\'ajouter à Photos a été refusée.'),
      _ => tr(zh: '保存失败(${error.code})。', en: 'Save failed (${error.code}).', zht: '儲存失敗（${error.code}）。', ja: '保存に失敗しました（${error.code}）。', es: 'No se pudo guardar (${error.code}).', pt: 'Falha ao salvar (${error.code}).', de: 'Sichern fehlgeschlagen (${error.code}).', fr: 'Échec de l\'enregistrement (${error.code}).'),
    };
  }
  return tr(zh: '出错了:$error', en: 'Something went wrong: $error', zht: '出錯了：$error', ja: 'エラーが発生しました：$error', es: 'Algo salió mal: $error', pt: 'Algo deu errado: $error', de: 'Etwas ist schiefgelaufen: $error', fr: 'Une erreur s\'est produite : $error');
}
