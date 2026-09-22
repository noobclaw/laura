import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';

/// OhmBench's one paywall.
///
/// It sells only what 1.0 ships: more circuits and bigger circuits. The
/// simulator, the scope, undo and saving are free and stay free — the free
/// tier is a real tool with a size limit, not a demo. M2 features (AC sweep,
/// transistors, iPad layout) are deliberately NOT listed: billing for
/// something the build does not do is an App Store 3.1.1 rejection.
///
/// Rule (2026-09-03): every app sells Pro through this sheet. No free-tier
/// gate may call `PurchaseService.instance.buyPro()` directly — the user must
/// first see what Pro adds and the store's real price, then tap Unlock. The
/// Pro flag is flipped by [PurchaseService]'s `onUnlocked` (wired in
/// main.dart), so a purchase made on another device restores through exactly
/// the same path. `reason` is the one-line explanation of which gate was hit
/// ("免费版最多 5 个日子,你已经用满了。").
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
                    Text('OhmBench Pro',
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
                // 3–4 perks, each one concrete thing Pro adds. Name the free
                // cap in the first one so the sheet answers "why am I here".
                _Perk(tr(
                  zh: '不限元件数 —— 免费版每张图 12 个元件,Pro 之后想画多大画多大',
                  en: 'Unlimited parts — the free version allows 12 per circuit, Pro lifts the cap',
                )),
                _Perk(tr(
                  zh: '不限电路数 —— 免费版保存 1 张,Pro 之后随意新建、复制',
                  en: 'Unlimited circuits — the free version keeps one, Pro lets you create and duplicate freely',
                )),
                _Perk(tr(
                  zh: '同一个引擎、同一套精度:免费版和 Pro 的仿真结果完全一样',
                  en: 'The same engine and the same accuracy — free and Pro give identical results',
                )),
                const SizedBox(height: 12),
                Text(
                  tr(
                    zh: '一次性买断 —— 没有订阅、没有账号、没有广告,数据依然只在你的手机里。',
                    en: 'A one-time purchase — no subscription, no account, no ads, and your data still never leaves the phone.',
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
                        zh: '解锁 —— ${price ?? '\$4.99'}',
                        en: 'Unlock — ${price ?? '\$4.99'}',
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
