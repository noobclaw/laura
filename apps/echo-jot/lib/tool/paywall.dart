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
  await showProSheet(
    context,
    reason: tr(
      zh: '免费版可保存 $freeNoteLimit 条笔记,你已经用满了。',
      en: 'The free tier keeps $freeNoteLimit notes — you have filled it.',
    ),
  );
  // A purchase that went through flips the persisted flag, so let the user start
  // dictating right away instead of making them tap the mic again.
  return store.pro;
}

/// The one-time Pro unlock sheet. Every gate (settings tile, note cap, partial
/// export) opens this rather than the store sheet directly, so the user sees
/// what Pro adds and the store's real price before anything is charged.
/// [reason] is the one-line explanation of which gate was hit.
Future<void> showProSheet(BuildContext context, {String? reason}) async {
  PurchaseService.instance.ensurePrice();
  final buy = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _UnlockSheet(reason: reason),
  );
  // Hands off to the store sheet. The result arrives on the purchase stream
  // (main.dart's onUnlocked), not from this call.
  if (buy == true) await PurchaseService.instance.buyPro();
}

class _UnlockSheet extends StatelessWidget {
  const _UnlockSheet({this.reason});
  final String? reason;

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
                reason ??
                    tr(
                      zh: '免费版可保存 $freeNoteLimit 条笔记。一次买断,永久使用。',
                      en: 'The free tier keeps $freeNoteLimit notes. Pay once, keep it forever.',
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
                      // USD base price until the store answers; the apps are
                      // not sold in mainland China, so a ¥ figure here was
                      // wrong for every real account.
                      storePrice ?? r'$4.99',
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
