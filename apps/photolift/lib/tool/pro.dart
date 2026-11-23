import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';

/// The one-time Pro unlock sheet — every free-tier gate (4x, the daily cap,
/// the corner tag, the settings row) opens this instead of jumping straight
/// into the store sheet, so the user sees what Pro adds and the real store
/// price before anything is charged. The Pro flag itself is flipped by
/// [PurchaseService]'s `onUnlocked` (wired in main.dart), so a purchase made
/// on another device restores through exactly the same path.
Future<void> showProSheet(BuildContext context, {String? reason}) {
  PurchaseService.instance.ensurePrice();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final text = Theme.of(ctx).textTheme;
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          cs.primary.withValues(alpha: 0.35),
                          cs.primary.withValues(alpha: 0.05),
                        ]),
                      ),
                      child: Icon(Icons.workspace_premium,
                          color: cs.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text('PixelLift Pro', style: text.titleLarge),
                  ],
                ),
                if (reason != null) ...[
                  const SizedBox(height: 10),
                  Text(reason,
                      style: text.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant, height: 1.4)),
                ],
                const SizedBox(height: 18),
                _Perk(tr(
                  zh: '不限张数 —— 免费版每天 3 张',
                  en: 'Unlimited photos — the free tier allows 3 a day', zht: '不限張數 —— 免費版每天 3 張', ja: '枚数無制限 —— 無料版は1日3枚まで', es: 'Fotos ilimitadas: la versión gratis permite 3 al día', pt: 'Fotos ilimitadas — a versão grátis permite 3 por dia', de: 'Unbegrenzt viele Fotos – gratis sind es 3 pro Tag', fr: 'Photos illimitées — la version gratuite en permet 3 par jour')),
                _Perk(tr(
                  zh: '4x 放大(免费版为 2x),老照片放到海报级尺寸',
                  en: '4x upscaling (free is 2x) — poster-size results', zht: '4x 放大（免費版為 2x），老照片放到海報級尺寸', ja: '4x 拡大（無料版は 2x）—— ポスターサイズまで', es: 'Ampliación 4x (gratis es 2x): resultados tamaño póster', pt: 'Ampliação 4x (grátis é 2x) — resultados em tamanho pôster', de: '4x-Vergrößerung (gratis 2x) – Ergebnisse in Postergröße', fr: 'Agrandissement 4x (2x en gratuit) — résultats format affiche')),
                _Perk(tr(
                  zh: '去掉结果角落的 PixelLift 小标签',
                  en: 'Removes the small PixelLift tag in the corner', zht: '去掉結果角落的 PixelLift 小標籤', ja: '結果の隅の PixelLift ロゴを消せます', es: 'Quita la pequeña marca PixelLift de la esquina', pt: 'Remove a pequena marca PixelLift do canto', de: 'Entfernt das kleine PixelLift-Zeichen in der Ecke', fr: 'Retire la petite marque PixelLift dans le coin')),
                const SizedBox(height: 12),
                Text(
                  tr(
                    zh: '一次性买断 —— 没有订阅、没有账号、没有广告,照片依然从不离开你的手机。',
                    en: 'A one-time purchase — no subscription, no account, no ads, and your photos still never leave the phone.', zht: '一次性買斷 —— 沒有訂閱、沒有帳號、沒有廣告，照片依然從不離開你的手機。', ja: '買い切り —— サブスクなし・アカウント不要・広告なし。写真はこれからも端末から出ません。', es: 'Un pago único: sin suscripción, sin cuenta, sin anuncios, y tus fotos siguen sin salir del teléfono.', pt: 'Uma compra única — sem assinatura, sem conta, sem anúncios, e suas fotos continuam sem sair do celular.', de: 'Ein Einmalkauf – kein Abo, kein Konto, keine Werbung, und deine Fotos verlassen das Telefon weiterhin nie.', fr: 'Un achat unique — sans abonnement, sans compte, sans pub, et vos photos ne quittent toujours pas le téléphone.'),
                  style: text.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      // Hands off to the store sheet. The result arrives on
                      // the purchase stream, not from this call.
                      PurchaseService.instance.buyPro();
                    },
                    // The store's own localized price once it answers; the
                    // written price only until then.
                    child: ValueListenableBuilder<String?>(
                      valueListenable: PurchaseService.instance.price,
                      builder: (context, price, _) => Text(tr(
                        zh: '解锁 —— ${price ?? '\$6.99'}',
                        en: 'Unlock — ${price ?? '\$6.99'}', zht: '解鎖 —— ${price ?? '\$6.99'}', ja: '解除する —— ${price ?? '\$6.99'}', es: 'Desbloquear: ${price ?? '\$6.99'}', pt: 'Desbloquear — ${price ?? '\$6.99'}', de: 'Freischalten – ${price ?? '\$6.99'}', fr: 'Débloquer — ${price ?? '\$6.99'}')),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      PurchaseService.instance.restore();
                    },
                    child: Text(tr(zh: '恢复购买', en: 'Restore purchases', zht: '恢復購買', ja: '購入を復元', es: 'Restaurar compras', pt: 'Restaurar compras', de: 'Käufe wiederherstellen', fr: 'Restaurer les achats')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Perk extends StatelessWidget {
  const _Perk(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.check_circle,
                size: 19, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }
}
