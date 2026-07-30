import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'note.dart';

/// Free tier: this many notes. The unlock is the single non-consumable
/// `pro_unlock` product handled by core/purchase.dart (real Play Billing).
const int freeNoteLimit = 30;

/// Returns true if the user may start another note. Shows the unlock sheet when
/// the free tier is full.
Future<bool> checkNoteQuota(BuildContext context, NoteStore store) async {
  if (store.pro || store.notes.length < freeNoteLimit) return true;
  final buy = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const _UnlockSheet(),
  );
  if (buy == true) await PurchaseService.instance.buyPro();
  // A purchase that went through flips the persisted flag, so let the user start
  // dictating right away instead of making them tap the mic again.
  return store.pro;
}

class _UnlockSheet extends StatelessWidget {
  const _UnlockSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final perks = <(IconData, String)>[
      (
        Icons.all_inclusive,
        tr(zh: '无限条笔记', en: 'Unlimited notes'),
      ),
      (
        Icons.ios_share_outlined,
        tr(zh: '一键导出全部笔记', en: 'Export every note at once'),
      ),
      (
        Icons.favorite_outline,
        tr(zh: '一次买断,没有订阅', en: 'One-time purchase, never a subscription'),
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: 0.14),
                ),
                child: Icon(Icons.workspace_premium_outlined,
                    size: 32, color: cs.primary),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                tr(zh: '解锁无限笔记', en: 'Unlock unlimited notes'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                tr(
                  zh: '免费版可保存 $freeNoteLimit 条笔记,你已经用满了。',
                  en: 'The free tier keeps $freeNoteLimit notes — you have filled it.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            // The price is the number this screen exists for — show it, and show
            // that it is one-time. (Display only; the store is the source of
            // truth at purchase time.)
            Center(
              child: Column(
                children: [
                  // The store's own localized price when it is known — a user
                  // billed in EUR must not read a ¥ figure here.
                  ValueListenableBuilder<String?>(
                    valueListenable: PurchaseService.instance.price,
                    builder: (context, storePrice, _) => Text(
                      storePrice ?? tr(zh: '¥28', en: r'$4.99'),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Text(
                    tr(zh: '一次付清 · 永久有效', en: 'One-time · yours forever'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  for (final (icon, label) in perks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Icon(icon, size: 20, color: cs.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(label,
                                style: Theme.of(context).textTheme.bodyLarge),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(tr(zh: '解锁 Pro', en: 'Unlock Pro')),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                  PurchaseService.instance.restore();
                },
                child: Text(tr(zh: '恢复购买', en: 'Restore purchase')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
