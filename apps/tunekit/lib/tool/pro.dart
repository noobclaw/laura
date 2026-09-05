import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'app_theme.dart';

/// The one-time Pro unlock, sold through the store as the non-consumable
/// `com.noobclaw.tunekit.pro_unlock`. Every free-tier gate in the app opens
/// this sheet (never `buyPro()` directly); the Pro flag is flipped by
/// [PurchaseService]'s `onUnlocked` (wired in main.dart), so a purchase made
/// on another device restores through exactly the same path.
///
/// [reason] names the gate that was hit, e.g. "吉他预设是 Pro 功能。".
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
                          kBeatAmber.withValues(alpha: 0.35),
                          kBeatAmber.withValues(alpha: 0.05),
                        ]),
                      ),
                      child: const Icon(Icons.workspace_premium,
                          color: kBeatAmber, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text(tr(zh: '调音节拍器 Pro', en: 'TuneBench Pro'),
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
                  zh: '吉他、尤克里里、小提琴、贝斯预设调音,每根弦一个按钮(免费版为半音模式)',
                  en: 'Guitar, ukulele, violin and bass presets with a button per string (free: chromatic mode)',
                )),
                _Perk(tr(
                  zh: '节拍器全部拍号与细分:6/8、三连音、十六分音符',
                  en: 'Every metre and subdivision on the metronome: 6/8, triplets, sixteenths',
                )),
                _Perk(tr(
                  zh: '完整和弦与音阶字典(近 50 种类型 × 12 个根音),全部可弹奏检查与随机训练',
                  en: 'The full chord and scale dictionary (about 50 types × 12 roots), all with play-and-check and drills',
                )),
                _Perk(tr(
                  zh: '练习记录不限天数,查看 30 天趋势(免费版保留最近 7 天)',
                  en: 'Unlimited practice history with 30-day trends (free keeps the last 7 days)',
                )),
                const SizedBox(height: 12),
                Text(
                  tr(
                    zh: '一次性买断 —— 没有订阅、没有账号、没有广告,声音和记录依然只在你的手机里。',
                    en: 'A one-time purchase — no subscription, no account, no ads, and your audio and log still never leave the phone.',
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
                    // written USD price only until then.
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
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.check_circle, size: 19, color: kInTuneGreen),
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
