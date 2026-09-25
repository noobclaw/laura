import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'app_theme.dart';

/// The only place the app may open the store sheet from (PIPELINE G3 rule,
/// 2026-09-03): every free-tier gate lands here first, so the writer sees what
/// Pro adds and the store's real price before anything is charged.
///
/// The perks listed here are the ones 1.0 actually ships. Sync, the Android
/// release and the research board are M2/M3 and are deliberately NOT sold
/// here — a paywall that bills for something the build does not do is an
/// App Store 3.1.1 rejection and, worse, is exactly the "felt deceived"
/// review this app exists to answer.
Future<void> showProSheet(BuildContext context, {String? reason}) {
  PurchaseService.instance.ensurePrice();
  return showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: DbMotion.sheetStyle(context),
    isScrollControlled: true,
    builder: (ctx) {
      final c = DbColors.of(ctx);
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(DbSpace.gutter, 0, DbSpace.gutter, DbSpace.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Draftbook Pro', style: DbType.heading.copyWith(color: c.ink)),
                if (reason != null) ...[
                  const SizedBox(height: DbSpace.x1),
                  Text(reason, style: DbType.body.copyWith(color: c.inkMuted)),
                ],
                const SizedBox(height: DbSpace.x2),
                _Perk(tr(
                  zh: '不限项目数：免费版写 1 本书，Pro 之后想开几本开几本',
                  en: 'Unlimited books: the free version keeps one, Pro lifts the cap',
                )),
                _Perk(tr(
                  zh: '导出 Word（.docx）：按章分页、标题带大纲级别，直接发给编辑',
                  en: 'Word (.docx) export: a page break per chapter and real heading '
                      'styles, ready to send to an editor',
                )),
                _Perk(tr(
                  zh: '免费版有的都还在：无限字数、大纲拖拽、版本历史、TXT / Markdown 导出',
                  en: 'Everything the free version already had stays: unlimited words, '
                      'the draggable outline, version history, TXT / Markdown export',
                )),
                const SizedBox(height: DbSpace.x1_5),
                Text(
                  tr(
                    zh: '一次性买断：没有订阅、没有账号、不联网，稿子依然只在你的手机里。'
                        '换机后用「恢复购买」找回。',
                    en: 'A one-time purchase: no subscription, no account, no network, '
                        'and your manuscript still never leaves the phone. '
                        'Use "Restore purchases" on a new device.',
                  ),
                  style: DbType.meta.copyWith(color: c.inkMuted, height: 1.45),
                ),
                const SizedBox(height: DbSpace.x2_5),
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
                        zh: '解锁 Pro，${price ?? r'$9.99'}',
                        en: 'Unlock Pro, ${price ?? r'$9.99'}',
                      )),
                    ),
                  ),
                ),
                const SizedBox(height: DbSpace.x0_5),
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
    final c = DbColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DbSpace.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: DbSpace.x0_5),
            child: Icon(Icons.check, size: 18, color: c.accent),
          ),
          const SizedBox(width: DbSpace.x1_5),
          Expanded(child: Text(text, style: DbType.body.copyWith(color: c.ink))),
        ],
      ),
    );
  }
}