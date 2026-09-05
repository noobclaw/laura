import 'package:flutter/material.dart';

import '../core/branding.dart';
import '../core/l10n.dart';
import '../core/purchase.dart';
import 'store.dart';

/// Written USD base price (PLAN.md); the store's own localised price
/// replaces it as soon as StoreKit / Play answers.
const String kProFallbackPrice = '\$4.99';

/// The one-time Pro unlock sheet. Every free-tier gate — the batch cap, the
/// WebP export choice, watermark presets, remembered settings and the
/// settings-page Pro row — opens this instead of jumping into the store, so
/// the user sees what Pro adds and the real price before anything is
/// charged. The Pro flag itself is flipped by [PurchaseService]'s
/// `onUnlocked` (wired in main.dart), so a purchase made on another device
/// restores through exactly the same path.
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
                    Text('${Branding.appName} Pro', style: text.titleLarge),
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
                  zh: '不限张数批量处理(免费版每次最多 $kFreeBatchLimit 张)',
                  en: 'Unlimited batch size (free: up to $kFreeBatchLimit images per run)',
                )),
                _Perk(tr(
                  zh: '导出 WebP 格式',
                  en: 'Export to WebP',
                )),
                _Perk(tr(
                  zh: '保存水印预设,一键套用',
                  en: 'Save watermark presets and apply them in one tap',
                )),
                _Perk(tr(
                  zh: '每个工具记住你上次的设置',
                  en: 'Every tool remembers your last settings',
                )),
                const SizedBox(height: 12),
                Text(
                  tr(
                    zh: '一次性买断 —— 没有订阅、没有账号、没有广告,图片依然只在你的手机里。',
                    en: 'A one-time purchase — no subscription, no account, no ads, and your pictures still never leave the phone.',
                  ),
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
                    child: ValueListenableBuilder<String?>(
                      valueListenable: PurchaseService.instance.price,
                      builder: (context, price, _) => Text(tr(
                        zh: '解锁 —— ${price ?? kProFallbackPrice}',
                        en: 'Unlock — ${price ?? kProFallbackPrice}',
                      )),
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
                    child: Text(tr(zh: '恢复购买', en: 'Restore purchases')),
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
