import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'location_store.dart';

/// Presents the one-time Pro buyout, sold through the store as the
/// non-consumable `pro_unlock`. This sheet only launches the store sheet; the
/// Pro flag is flipped by [PurchaseService]'s `onUnlocked` (wired in main.dart),
/// so a purchase made on another device restores through the same path.
void showProSheet(BuildContext context, LocationStore store) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: Color(0xFFF5A623), size: 28),
              const SizedBox(width: 10),
              Text('GoldenScout Pro',
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 16),
          _Perk(tr(
              zh: '规划任意日期的光线,过去或未来',
              en: 'Plan the light for any date, past or future')),
          _Perk(tr(zh: '保存无限拍摄机位', en: 'Save unlimited shooting spots')),
          _Perk(tr(
              zh: '完整月亮详情:月升、月落与月相',
              en: 'Full moon details: rise, set & phase')),
          const SizedBox(height: 8),
          Text(
              tr(
                  zh: '一次性买断——无订阅、无账号。',
                  en: 'One-time purchase — no subscription, no account.'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Hands off to the store sheet. The result arrives on the
                // purchase stream, not from this call.
                PurchaseService.instance.buyPro();
              },
              // The store's own localized price once it answers; the written
              // price only until then.
              child: ValueListenableBuilder<String?>(
                valueListenable: PurchaseService.instance.price,
                builder: (context, price, _) => Text(
                  tr(
                    zh: '解锁——${price ?? '\$3.99'}',
                    en: 'Unlock — ${price ?? '\$3.99'}',
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                PurchaseService.instance.restore();
              },
              child: Text(tr(zh: '恢复购买', en: 'Restore purchases')),
            ),
          ),
        ],
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
          const Icon(Icons.check_circle, size: 20, color: Color(0xFFF5A623)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
