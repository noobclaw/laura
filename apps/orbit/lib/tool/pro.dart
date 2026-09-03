import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'app_theme.dart';
import 'store.dart';

/// The one-time Pro unlock, sold through the store as the non-consumable
/// `pro_unlock`. The sheet only launches the store sheet; the Pro flag is
/// flipped by [PurchaseService]'s `onUnlocked` (wired in main.dart), so a
/// purchase made on another device restores through exactly the same path.
void showProSheet(BuildContext context, OrbitStore store) {
  PurchaseService.instance.ensurePrice();
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
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
                        kSignalAmber.withValues(alpha: 0.35),
                        kSignalAmber.withValues(alpha: 0.05),
                      ]),
                    ),
                    child: const Icon(Icons.workspace_premium,
                        color: kSignalAmber, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text('Orbit Pro',
                      style: Theme.of(sheetContext).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 18),
              _Perk(tr(
                zh: '全部 ${store.catalog.length} 个亮目标,不只是 8 个精选',
                en: 'All ${store.catalog.length} bright targets, not just the 8 headliners',
              )),
              _Perk(tr(
                zh: '预报窗口拉到 10 天,提前安排一次观测',
                en: 'Forecast out to 10 days — plan an outing, not just tonight',
              )),
              _Perk(tr(
                zh: '导入你自己关心的轨道根数',
                en: 'Import element sets for whatever you care about',
              )),
              _Perk(tr(
                zh: '显示暗过境与 5° 低仰角过境(无线电/望远镜用)',
                en: 'Show eclipsed and low 5° passes, for radio and scope work',
              )),
              const SizedBox(height: 12),
              Text(
                tr(
                  zh: '一次性买断 —— 没有订阅、没有账号、没有广告,也依然不联网。',
                  en: 'A one-time purchase — no subscription, no account, no ads, and still no network access.',
                ),
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                      color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    // Hands off to the store sheet. The result arrives on the
                    // purchase stream, not from this call.
                    PurchaseService.instance.buyPro();
                  },
                  // The store's own localized price once it answers; the
                  // written price only until then.
                  child: ValueListenableBuilder<String?>(
                    valueListenable: PurchaseService.instance.price,
                    builder: (context, price, _) => Text(
                      tr(
                        zh: '解锁 —— ${price ?? '\$3.99'}',
                        en: 'Unlock — ${price ?? '\$3.99'}',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    PurchaseService.instance.restore();
                  },
                  child: Text(tr(zh: '恢复购买', en: 'Restore purchases')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
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
            child: Icon(Icons.check_circle, size: 19, color: kOrbitCyan),
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
