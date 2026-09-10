import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'store.dart';

/// The one place the store's payment sheet may be opened from.
///
/// Every free-tier gate calls this first: it names the gate that was hit,
/// lists what Pro adds, shows the store's own localised price and offers
/// Restore. Nothing else in the app calls `PurchaseService.buyPro()`.
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
                      child: Icon(Icons.workspace_premium, color: cs.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text('AstroPile Pro', style: text.titleLarge),
                  ],
                ),
                if (reason != null) ...[
                  const SizedBox(height: 10),
                  Text(reason,
                      style: text.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
                ],
                const SizedBox(height: 18),
                _Perk(tr(
                  zh: '一次最多叠 $kProFrameLimit 张(免费版 $kFreeFrameLimit 张)——帧数越多,噪点越少',
                  en: 'Stack up to $kProFrameLimit frames at a time (free: $kFreeFrameLimit) — more frames, less noise',
                )),
                _Perk(tr(
                  zh: '中值叠加:自动去掉飞机、卫星拖线和热噪点',
                  en: 'Median stacking: aircraft, satellite trails and hot pixels drop out on their own',
                )),
                _Perk(tr(
                  zh: '记住你的叠加方式与工作分辨率',
                  en: 'Remembers your stacking mode and working resolution',
                )),
                const SizedBox(height: 12),
                Text(
                  tr(
                    zh: '一次性买断 —— 没有订阅、没有账号、没有广告,照片依然只在你的手机里处理。逐帧对齐报告在免费版一样完整可用。',
                    en: 'A one-time purchase — no subscription, no account, no ads, and photos are still processed only on your phone. The per-frame alignment report stays fully available on the free tier.',
                  ),
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }
}
