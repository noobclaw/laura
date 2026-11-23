import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'compare_slider.dart';
import 'job_runner.dart';
import 'media.dart';
import 'models.dart';
import 'pro.dart';
import 'store.dart';

/// The before/after view for one result, with save / share / delete.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.record,
    required this.store,
    required this.fresh,
  });

  final LiftRecord record;
  final PhotoLiftStore store;
  /// Just produced (title says so) vs. opened from history.
  final bool fresh;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

enum _View { compare, zoom }

class _ResultScreenState extends State<ResultScreen> {
  _View _view = _View.compare;
  bool _busy = false;
  /// The compare divider sweeps once per visit, not every time the user
  /// flips between compare and zoom.
  bool _swept = false;

  LiftRecord get r => widget.record;
  File get _out => File(widget.store.outputPath(r));
  File get _src => File(widget.store.sourcePath(r));

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final stamp = r.createdAt.toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first;
      await MediaBridge.saveToGallery(_out.path, displayName: 'PixelLift_${stamp}_${r.scale}x.jpg');
      if (!mounted) return;
      _snack(tr(zh: '已保存到相册', en: 'Saved to Photos', zht: '已儲存到相簿', ja: '写真に保存しました', es: 'Guardado en Fotos', pt: 'Salvo em Fotos', de: 'In Fotos gesichert', fr: 'Enregistré dans Photos'));
    } on MediaException catch (e) {
      if (!mounted) return;
      if (e.code == 'permission_denied') {
        _snack(
          tr(zh: '没有写入相册的权限,请在系统设置里允许「添加照片」。',
              en: 'Permission to add to Photos was denied — allow "Add Photos" in Settings.', zht: '沒有寫入相簿的權限，請在系統設定裡允許「加入照片」。', ja: '写真への追加が許可されていません。設定で「写真を追加」を許可してください。', es: 'Se denegó el permiso para añadir a Fotos: permite "Añadir fotos" en Ajustes.', pt: 'A permissão para adicionar a Fotos foi negada — permita "Adicionar fotos" em Ajustes.', de: 'Die Berechtigung zum Hinzufügen zu Fotos wurde verweigert – erlaube „Fotos hinzufügen“ in den Einstellungen.', fr: 'L\'autorisation d\'ajouter à Photos a été refusée — autorisez « Ajouter des photos » dans Réglages.'),
          action: SnackBarAction(
              label: tr(zh: '去设置', en: 'Settings', zht: '設定', ja: '設定', es: 'Ajustes', pt: 'Ajustes', de: 'Einstellungen', fr: 'Réglages'), onPressed: MediaBridge.openSettings),
        );
      } else {
        _snack(describeUpscaleError(e));
      }
    } catch (e) {
      if (mounted) _snack(describeUpscaleError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(BuildContext btnContext) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // iPad presents the share sheet as a popover and needs an origin rect.
      final box = btnContext.findRenderObject() as RenderBox?;
      final origin = box != null && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(_out.path, mimeType: 'image/jpeg')],
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      if (mounted) _snack(tr(zh: '分享失败:$e', en: 'Share failed: $e', zht: '分享失敗：$e', ja: '共有に失敗しました：$e', es: 'No se pudo compartir: $e', pt: 'Falha ao compartilhar: $e', de: 'Teilen fehlgeschlagen: $e', fr: 'Échec du partage : $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '删除这条记录?', en: 'Delete this result?', zht: '刪除這筆紀錄？', ja: 'この結果を削除しますか？', es: '¿Eliminar este resultado?', pt: 'Excluir este resultado?', de: 'Dieses Ergebnis löschen?', fr: 'Supprimer ce résultat ?')),
        content: Text(tr(
          zh: '会删除应用内的原图副本和修复结果;已保存到相册的照片不受影响。',
          en: 'Removes the in-app source copy and result; anything already saved to Photos stays.', zht: '會刪除應用內的原圖副本和修復結果；已儲存到相簿的照片不受影響。', ja: 'アプリ内の元画像のコピーと結果を削除します。写真に保存済みのものは残ります。', es: 'Elimina la copia original y el resultado de la app; lo que ya guardaste en Fotos se queda.', pt: 'Remove a cópia original e o resultado do app; o que já foi salvo em Fotos fica.', de: 'Entfernt die App-Kopie des Originals und das Ergebnis; bereits in Fotos Gesichertes bleibt.', fr: 'Supprime la copie d\'origine et le résultat dans l\'app ; ce qui est déjà dans Photos reste.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(zh: '取消', en: 'Cancel', zht: '取消', ja: 'キャンセル', es: 'Cancelar', pt: 'Cancelar', de: 'Abbrechen', fr: 'Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(zh: '删除', en: 'Delete', zht: '刪除', ja: '削除', es: 'Eliminar', pt: 'Excluir', de: 'Löschen', fr: 'Supprimer'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.store.deleteRecord(r);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final aspect = r.outWidth > 0 && r.outHeight > 0 ? r.outWidth / r.outHeight : 4 / 3;
    final missing = !_out.existsSync();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fresh
            ? tr(zh: '修复完成', en: 'Restored', zht: '修復完成', ja: '復元しました', es: 'Restaurada', pt: 'Restaurada', de: 'Restauriert', fr: 'Restaurée')
            : tr(zh: '修复结果', en: 'Result', zht: '修復結果', ja: '結果', es: 'Resultado', pt: 'Resultado', de: 'Ergebnis', fr: 'Résultat')),
        actions: [
          IconButton(
            tooltip: tr(zh: '删除', en: 'Delete', zht: '刪除', ja: '削除', es: 'Eliminar', pt: 'Excluir', de: 'Löschen', fr: 'Supprimer'),
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : _delete,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            if (missing)
              _MissingCard()
            else ...[
              SegmentedButton<_View>(
                segments: [
                  ButtonSegment(
                      value: _View.compare,
                      icon: const Icon(Icons.compare),
                      label: Text(tr(zh: '前后对比', en: 'Compare', zht: '前後對比', ja: '比較', es: 'Comparar', pt: 'Comparar', de: 'Vergleichen', fr: 'Comparer'))),
                  ButtonSegment(
                      value: _View.zoom,
                      icon: const Icon(Icons.zoom_in),
                      label: Text(tr(zh: '放大细看', en: 'Zoom', zht: '放大細看', ja: 'ズーム', es: 'Zoom', pt: 'Zoom', de: 'Zoom', fr: 'Zoom'))),
                ],
                selected: {_view},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
              const SizedBox(height: 12),
              if (_view == _View.compare)
                CompareSlider(
                  before: _src,
                  after: _out,
                  aspectRatio: aspect.clamp(0.4, 2.5),
                  autoSweep: !_swept,
                  onSweepEnd: () => _swept = true,
                )
              else
                _ZoomView(file: _out, aspectRatio: aspect.clamp(0.4, 2.5)),
              const SizedBox(height: 8),
              Text(
                _view == _View.compare
                    ? tr(zh: '左右拖动分界线对比', en: 'Drag the divider to compare', zht: '左右拖動分界線對比', ja: '境界線をドラッグして比較', es: 'Arrastra la línea para comparar', pt: 'Arraste a linha para comparar', de: 'Trennlinie ziehen zum Vergleichen', fr: 'Faites glisser la ligne pour comparer')
                    : tr(zh: '双指缩放查看细节', en: 'Pinch to inspect the detail', zht: '雙指縮放查看細節', ja: 'ピンチで細部を確認', es: 'Pellizca para ver los detalles', pt: 'Faça pinça para ver os detalhes', de: 'Mit zwei Fingern zoomen für Details', fr: 'Pincez pour voir les détails'),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            if (r.engine == EngineKind.dartFallback) ...[
              _Notice(
                icon: Icons.info_outline,
                color: cs.tertiaryContainer,
                onColor: cs.onTertiaryContainer,
                text: tr(
                  zh: '这次用的是基础放大(此设备上 AI 引擎不可用),效果会弱于 AI 修复。',
                  en: 'This result used basic resampling — the AI engine is not available on this device, so it is weaker than an AI restore.', zht: '這次用的是基礎放大（此裝置上 AI 引擎無法使用），效果會弱於 AI 修復。', ja: '今回は標準の拡大を使いました（この端末では AI エンジンが使えません）。AI 復元より効果は控えめです。', es: 'Este resultado usó ampliación básica: el motor de IA no está disponible en este dispositivo, así que el efecto es menor que con IA.', pt: 'Este resultado usou ampliação básica — o motor de IA não está disponível neste aparelho, então o efeito é menor que com IA.', de: 'Dieses Ergebnis nutzt einfaches Skalieren – die KI-Engine ist auf diesem Gerät nicht verfügbar, daher schwächer als eine KI-Restaurierung.', fr: 'Ce résultat utilise un agrandissement simple — le moteur d\'IA n\'est pas disponible sur cet appareil, l\'effet est donc moindre.'),
              ),
              const SizedBox(height: 12),
            ],
            _StatsStrip(record: r, animate: widget.fresh || !_swept),
            if (r.tagged && !widget.store.pro) ...[
              const SizedBox(height: 12),
              _Notice(
                icon: Icons.sell_outlined,
                color: cs.surfaceContainerHigh,
                onColor: cs.onSurfaceVariant,
                text: tr(
                  zh: '右下角有一个小小的 PixelLift 标签。升级 Pro 后不再添加。',
                  en: 'A small PixelLift tag sits in the bottom-right corner. Pro results carry no tag.', zht: '右下角有一個小小的 PixelLift 標籤。升級 Pro 後不再添加。', ja: '右下に小さな PixelLift ロゴが入っています。Pro では入りません。', es: 'Hay una pequeña marca PixelLift en la esquina inferior derecha. Los resultados Pro no la llevan.', pt: 'Há uma pequena marca PixelLift no canto inferior direito. Os resultados Pro não têm marca.', de: 'Unten rechts sitzt ein kleines PixelLift-Zeichen. Pro-Ergebnisse haben keins.', fr: 'Une petite marque PixelLift figure en bas à droite. Les résultats Pro n\'en ont pas.'),
                action: TextButton(
                  onPressed: () => showProSheet(context),
                  child: Text(tr(zh: '了解 Pro', en: 'About Pro', zht: '了解 Pro', ja: 'Pro について', es: 'Sobre Pro', pt: 'Sobre o Pro', de: 'Über Pro', fr: 'À propos de Pro')),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (!missing)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_alt),
                      label: Text(tr(zh: '保存到相册', en: 'Save to Photos', zht: '儲存到相簿', ja: '写真に保存', es: 'Guardar en Fotos', pt: 'Salvar em Fotos', de: 'In Fotos sichern', fr: 'Enregistrer dans Photos')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Builder(
                      builder: (btnCtx) => OutlinedButton.icon(
                        onPressed: _busy ? null : () => _share(btnCtx),
                        icon: const Icon(Icons.ios_share),
                        label: Text(tr(zh: '分享', en: 'Share', zht: '分享', ja: '共有', es: 'Compartir', pt: 'Compartilhar', de: 'Teilen', fr: 'Partager')),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomView extends StatelessWidget {
  const _ZoomView({required this.file, required this.aspectRatio});
  final File file;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: cs.surfaceContainerHighest,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            // Full-resolution decode: the whole point of this view.
            child: Image.file(file, fit: BoxFit.contain, filterQuality: FilterQuality.high),
          ),
        ),
      ),
    );
  }
}

/// Time / scale / resolution as three counters that roll up to their values
/// on arrival (TweenAnimationBuilder), plus the denoise + engine caption.
/// The resolution counts from the input size to the output size — the
/// number literally grows.
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.record, required this.animate});
  final LiftRecord record;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final r = record;
    final zh = isZhLocale;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final dur = animate && !reduce
        ? const Duration(milliseconds: 900)
        : Duration.zero;
    String fmtSecs(double v) {
      final cjk = zh || AppLanguage.effectiveCode == 'ja';
      if (v < 60) return cjk ? '${v.toStringAsFixed(1)} 秒' : '${v.toStringAsFixed(1)} s';
      final m = v ~/ 60;
      final sec = (v - m * 60).round();
      return cjk ? '$m 分 $sec 秒' : '${m}m ${sec}s';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: tr(zh: '用时', en: 'Time', zht: '用時', ja: '所要時間', es: 'Tiempo', pt: 'Tempo', de: 'Dauer', fr: 'Durée'),
                    duration: dur,
                    end: r.elapsedMs / 1000,
                    format: fmtSecs,
                  ),
                ),
                _vDivider(cs),
                Expanded(
                  child: _StatTile(
                    label: tr(zh: '放大倍数', en: 'Upscale', zht: '放大倍數', ja: '拡大倍率', es: 'Ampliación', pt: 'Ampliação', de: 'Vergrößerung', fr: 'Agrandissement'),
                    duration: dur,
                    end: r.scale.toDouble(),
                    format: (v) => '${v.round()}x',
                    accent: true,
                  ),
                ),
                _vDivider(cs),
                Expanded(
                  flex: 2,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: animate ? 0.0 : 1.0, end: 1.0),
                    duration: dur,
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) {
                      final w = (r.inWidth + (r.outWidth - r.inWidth) * t).round();
                      final h = (r.inHeight + (r.outHeight - r.inHeight) * t).round();
                      return _StatText(
                        label: tr(zh: '分辨率', en: 'Resolution', zht: '解析度', ja: '解像度', es: 'Resolución', pt: 'Resolução', de: 'Auflösung', fr: 'Résolution'),
                        value: '$w × $h',
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${tr(zh: '降噪', en: 'Denoise', zht: '降噪', ja: 'ノイズ除去', es: 'Reducir ruido', pt: 'Reduzir ruído', de: 'Entrauschen', fr: 'Débruitage')} ${r.denoise.label} · '
              '${r.engine.label} · ${r.inWidth} × ${r.inHeight} → ${r.outWidth} × ${r.outHeight}',
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _vDivider(ColorScheme cs) => Container(
        width: 1,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: cs.outlineVariant.withValues(alpha: 0.6),
      );
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.duration,
    required this.end,
    required this.format,
    this.accent = false,
  });
  final String label;
  final Duration duration;
  final double end;
  final String Function(double) format;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: duration == Duration.zero ? end : 0.0, end: end),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => _StatText(label: label, value: format(v), accent: accent),
    );
  }
}

class _StatText extends StatelessWidget {
  const _StatText({required this.label, required this.value, this.accent = false});
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        // Shrink a long figure ("12m 34s", "4000 × 3000") to fit the
        // column instead of cutting it off with an ellipsis.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: accent ? (Theme.of(context).brightness == Brightness.dark ? kLiftGold : cs.primary) : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.onColor,
    required this.text,
    this.action,
  });
  final IconData icon;
  final Color color;
  final Color onColor;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, color: onColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: onColor, height: 1.4))),
          ?action,
        ],
      ),
    );
  }
}

class _MissingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
          color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Icon(Icons.broken_image_outlined, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            tr(zh: '结果文件已不存在(可能被系统清理)。可以删除这条记录。',
                en: 'The result file is gone (the system may have cleaned it up). You can delete this entry.', zht: '結果檔案已不存在（可能被系統清理）。可以刪除這筆紀錄。', ja: '結果ファイルが見つかりません（システムに削除された可能性があります）。この項目は削除できます。', es: 'El archivo del resultado ya no existe (puede que el sistema lo haya borrado). Puedes eliminar esta entrada.', pt: 'O arquivo do resultado não existe mais (o sistema pode tê-lo apagado). Você pode excluir esta entrada.', de: 'Die Ergebnisdatei ist weg (vielleicht vom System bereinigt). Du kannst diesen Eintrag löschen.', fr: 'Le fichier du résultat n\'existe plus (le système l\'a peut-être nettoyé). Vous pouvez supprimer cette entrée.'),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
