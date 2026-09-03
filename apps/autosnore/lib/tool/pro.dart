import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';

/// The one-time Pro unlock sheet — every free-tier gate (settings tile, the
/// report-screen card, history beyond the free nights) opens this instead of
/// jumping straight into the store sheet, so the user sees what Pro adds and
/// the real store price before anything is charged. The Pro flag itself is
/// flipped by [PurchaseService]'s `onUnlocked` (wired in main.dart), so a
/// purchase made on another device restores through exactly the same path.
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
                    Text(tr(zh: '鼾声记录 Pro', en: 'AutoSnore Pro'),
                        style: text.titleLarge),
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
                  zh: '无限历史 —— 免费版只保留最近 3 晚',
                  en: 'Unlimited history — the free tier keeps the last 3 nights',
                )),
                _Perk(tr(
                  zh: '跨夜趋势,看打鼾是变好还是变糟',
                  en: 'Night-to-night trends, to see whether it is improving',
                )),
                _Perk(tr(
                  zh: '两晚对比 —— 换枕头、戒酒后到底有没有用',
                  en: 'Compare two nights — did the new pillow actually help?',
                )),
                _Perk(tr(
                  zh: 'CSV 导出,带去给医生看',
                  en: 'CSV export to bring to your doctor',
                )),
                const SizedBox(height: 12),
                Text(
                  tr(
                    zh: '一次性买断 —— 没有订阅、没有账号、没有广告,录音依然不出手机。',
                    en: 'A one-time purchase — no subscription, no account, no ads, and your audio still never leaves the phone.',
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
                    // The store's own localized price once it answers; the
                    // written price only until then.
                    child: ValueListenableBuilder<String?>(
                      valueListenable: PurchaseService.instance.price,
                      builder: (context, price, _) => Text(tr(
                        zh: '解锁 —— ${price ?? '\$3.99'}',
                        en: 'Unlock — ${price ?? '\$3.99'}',
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
