import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/day_change.dart';
import '../core/l10n.dart';
import '../core/purchase.dart';
import 'home_screen.dart';
import 'job_runner.dart';
import 'models.dart';
import 'pro.dart';
import 'store.dart';
import 'tool_module.dart';

/// PhotoLift: on-device Real-ESRGAN upscaling for old photos.
class PhotoLiftTool extends ToolModule {
  PhotoLiftTool() {
    runner = LiftJobRunner(store);
    store.load();
    // The free allowance is per local day: re-render the quota card when the
    // day changes under an open app (midnight, or resume on a later day).
    _dayChange
      ..addListener(store.dayChanged)
      ..start();
  }

  final PhotoLiftStore store = PhotoLiftStore();
  late final LiftJobRunner runner;
  final DayChangeNotifier _dayChange = DayChangeNotifier();

  @override
  Widget buildHome(BuildContext context) => HomeScreen(store: store, runner: runner);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        _ProTile(store: store),
        _GpuTile(store: store),
        _DenoiseTile(store: store),
        _LibraryTile(store: store),
      ];
}

class _ProTile extends StatelessWidget {
  const _ProTile({required this.store});
  final PhotoLiftStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.workspace_premium, color: cs.primary),
              title: Text(store.pro
                  ? tr(zh: 'PixelLift Pro 已解锁', en: 'PixelLift Pro unlocked', zht: 'PixelLift Pro 已解鎖', ja: 'PixelLift Pro 解除済み', es: 'PixelLift Pro desbloqueado', pt: 'PixelLift Pro desbloqueado', de: 'PixelLift Pro freigeschaltet', fr: 'PixelLift Pro débloqué')
                  : tr(zh: '升级 PixelLift Pro', en: 'Upgrade to PixelLift Pro', zht: '升級 PixelLift Pro', ja: 'PixelLift Pro にアップグレード', es: 'Mejorar a PixelLift Pro', pt: 'Atualizar para PixelLift Pro', de: 'Upgrade auf PixelLift Pro', fr: 'Passer à PixelLift Pro')),
              subtitle: store.pro
                  ? Text(tr(zh: '不限张数 · 4x · 无标签', en: 'Unlimited · 4x · no tag', zht: '不限張數 · 4x · 無標籤', ja: '枚数無制限 · 4x · ロゴなし', es: 'Ilimitado · 4x · sin marca', pt: 'Ilimitado · 4x · sem marca', de: 'Unbegrenzt · 4x · ohne Zeichen', fr: 'Illimité · 4x · sans marque'))
                  : Text(tr(zh: '一次买断,无订阅', en: 'One-time purchase', zht: '一次買斷，無訂閱', ja: '買い切り・サブスクなし', es: 'Pago único', pt: 'Compra única', de: 'Einmalkauf', fr: 'Achat unique'),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: store.pro
                  ? null
                  : FilledButton.tonal(
                      onPressed: () => showProSheet(context),
                      child: const ProPriceText(fallback: '\$6.99'),
                    ),
              onTap: store.pro ? null : () => showProSheet(context),
            ),
            RestorePurchasesTile(pro: store.pro),
          ],
        );
      },
    );
  }
}

class _GpuTile extends StatelessWidget {
  const _GpuTile({required this.store});
  final PhotoLiftStore store;

  @override
  Widget build(BuildContext context) {
    // The iOS build of the engine is CPU-only (see PLAN.md), so the switch
    // would be a lie there; it is an Android-only setting, not a code path.
    if (!Platform.isAndroid) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => SwitchListTile(
        secondary: const Icon(Icons.memory),
        title: Text(tr(zh: 'GPU 加速', en: 'GPU acceleration', zht: 'GPU 加速', ja: 'GPU アクセラレーション', es: 'Aceleración GPU', pt: 'Aceleração por GPU', de: 'GPU-Beschleunigung', fr: 'Accélération GPU')),
        subtitle: Text(tr(
          zh: '用 Vulkan 跑模型,通常快 5-10 倍。出现花屏或失败时关闭。',
          en: 'Runs the model on Vulkan, usually 5-10x faster. Turn off if results look corrupted or fail.', zht: '用 Vulkan 執行模型，通常快 5-10 倍。出現花屏或失敗時關閉。', ja: 'Vulkan でモデルを実行し、通常 5〜10 倍高速です。結果が乱れたり失敗したりする場合はオフにしてください。', es: 'Ejecuta el modelo con Vulkan, normalmente 5-10 veces más rápido. Desactívalo si los resultados salen dañados o fallan.', pt: 'Roda o modelo com Vulkan, geralmente 5-10x mais rápido. Desative se os resultados saírem corrompidos ou falharem.', de: 'Führt das Modell mit Vulkan aus, meist 5–10× schneller. Ausschalten, wenn Ergebnisse fehlerhaft aussehen oder scheitern.', fr: 'Exécute le modèle avec Vulkan, en général 5 à 10 fois plus vite. Désactivez si les résultats sont corrompus ou échouent.')),
        value: store.useGpu,
        onChanged: store.setUseGpu,
      ),
    );
  }
}

class _DenoiseTile extends StatelessWidget {
  const _DenoiseTile({required this.store});
  final PhotoLiftStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => ListTile(
        leading: const Icon(Icons.blur_on),
        title: Text(tr(zh: '默认降噪', en: 'Default denoise', zht: '預設降噪', ja: '標準のノイズ除去', es: 'Reducción de ruido predeterminada', pt: 'Redução de ruído padrão', de: 'Standard-Entrauschen', fr: 'Débruitage par défaut')),
        subtitle: Text(store.defaultDenoise.label),
        onTap: () async {
          final picked = await showDialog<DenoiseLevel>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: Text(tr(zh: '默认降噪', en: 'Default denoise', zht: '預設降噪', ja: '標準のノイズ除去', es: 'Reducción de ruido predeterminada', pt: 'Redução de ruído padrão', de: 'Standard-Entrauschen', fr: 'Débruitage par défaut')),
              children: [
                for (final d in DenoiseLevel.values)
                  RadioListTile<DenoiseLevel>(
                    value: d,
                    // ignore: deprecated_member_use
                    groupValue: store.defaultDenoise,
                    title: Text(d.label),
                    // ignore: deprecated_member_use
                    onChanged: (v) => Navigator.pop(ctx, v),
                  ),
              ],
            ),
          );
          if (picked != null) store.setDefaultDenoise(picked);
        },
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({required this.store});
  final PhotoLiftStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => FutureBuilder<int>(
        future: store.libraryBytes(),
        builder: (context, snap) {
          final mb = (snap.data ?? 0) / (1024 * 1024);
          return ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr(zh: '清空修复记录', en: 'Clear history', zht: '清空修復紀錄', ja: '履歴を消去', es: 'Borrar historial', pt: 'Limpar histórico', de: 'Verlauf löschen', fr: 'Effacer l\'historique')),
            subtitle: Text(tr(
              zh: '${store.history.length} 张 · ${mb.toStringAsFixed(1)} MB(只删应用内副本,不动相册)',
              en: '${store.history.length} photos · ${mb.toStringAsFixed(1)} MB (in-app copies only, Photos untouched)', zht: '${store.history.length} 張 · ${mb.toStringAsFixed(1)} MB（只刪應用內副本，不動相簿）', ja: '${store.history.length} 枚 · ${mb.toStringAsFixed(1)} MB（アプリ内のコピーのみ削除。写真ライブラリは変更しません）', es: '${store.history.length} fotos · ${mb.toStringAsFixed(1)} MB (solo copias de la app; Fotos no se toca)', pt: '${store.history.length} fotos · ${mb.toStringAsFixed(1)} MB (só cópias do app; Fotos não é alterado)', de: '${store.history.length} Fotos · ${mb.toStringAsFixed(1)} MB (nur App-Kopien, Fotos bleibt unberührt)', fr: '${store.history.length} photos · ${mb.toStringAsFixed(1)} Mo (copies de l\'app uniquement, Photos intact)')),
            enabled: store.history.isNotEmpty,
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(tr(zh: '清空修复记录?', en: 'Clear history?', zht: '清空修復紀錄？', ja: '履歴を消去しますか？', es: '¿Borrar el historial?', pt: 'Limpar o histórico?', de: 'Verlauf löschen?', fr: 'Effacer l\'historique ?')),
                  content: Text(tr(
                    zh: '会删除应用内保存的全部原图副本和修复结果。已保存到相册的照片不受影响。',
                    en: 'Deletes every source copy and result kept inside the app. Photos already saved to your library are not affected.', zht: '會刪除應用內保存的全部原圖副本和修復結果。已儲存到相簿的照片不受影響。', ja: 'アプリ内に保存された元画像のコピーと結果をすべて削除します。写真ライブラリに保存済みの写真は影響を受けません。', es: 'Borra todas las copias originales y resultados guardados dentro de la app. Las fotos ya guardadas en tu fototeca no se ven afectadas.', pt: 'Apaga todas as cópias originais e resultados guardados no app. As fotos já salvas na sua fototeca não são afetadas.', de: 'Löscht alle in der App gespeicherten Original-Kopien und Ergebnisse. Bereits in deiner Mediathek gesicherte Fotos bleiben erhalten.', fr: 'Supprime toutes les copies d\'origine et tous les résultats conservés dans l\'app. Les photos déjà enregistrées dans votre photothèque ne sont pas touchées.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(tr(zh: '取消', en: 'Cancel', zht: '取消', ja: 'キャンセル', es: 'Cancelar', pt: 'Cancelar', de: 'Abbrechen', fr: 'Annuler'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(tr(zh: '清空', en: 'Clear', zht: '清空', ja: '消去', es: 'Borrar', pt: 'Limpar', de: 'Löschen', fr: 'Effacer'))),
                  ],
                ),
              );
              if (ok == true) await store.clearHistory();
            },
          );
        },
      ),
    );
  }
}
