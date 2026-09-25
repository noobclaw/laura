import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'app_theme.dart';
import 'haptics.dart';
import 'models.dart';
import 'pro.dart';
import 'store.dart';
import 'tool_module.dart';
import 'ui/home_screen.dart';

/// Draftbook — an offline organiser for long-form writing.
class DraftbookTool extends ToolModule {
  DraftbookTool();

  final DraftbookStore store = DraftbookStore();

  @override
  Widget buildHome(BuildContext context) => HomeScreen(store: store);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        _ProTile(store: store),
        ValueListenableBuilder<bool>(
          valueListenable: Haptics.enabled,
          builder: (context, on, _) => SwitchListTile.adaptive(
            secondary: const Icon(Icons.vibration),
            title: Text(tr(zh: '触感反馈', en: 'Haptics')),
            subtitle: Text(tr(
              zh: '按格式键、换回版本、写到每日目标时轻震一下',
              en: 'A light tap for format keys, restores and reaching the daily goal',
            )),
            value: on,
            activeTrackColor: DbColors.of(context).accent,
            onChanged: Haptics.setEnabled,
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => RestorePurchasesTile(pro: store.pro),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: Text(tr(zh: '这台设备上的稿子', en: 'On this device')),
            subtitle: Text(tr(
              zh: '${store.projects.length} 本书，'
                  '${groupedCount(store.projects.fold(0, (a, p) => a + p.words))} 字，'
                  '每个场景保留最近 ${Scene.maxHistory} 个版本',
              en: '${store.projects.length} books, '
                  '${groupedCount(store.projects.fold(0, (a, p) => a + p.words))} words; '
                  'the last ${Scene.maxHistory} versions of every scene are kept',
            )),
          ),
        ),
      ];
}

class _ProTile extends StatelessWidget {
  const _ProTile({required this.store});
  final DraftbookStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.pro) {
          return ListTile(
            leading: Icon(Icons.verified, color: DbColors.of(context).accent),
            title: Text(tr(zh: '已解锁 Pro', en: 'Pro unlocked')),
            subtitle: Text(tr(
              zh: '不限项目数与 Word 导出，感谢支持',
              en: 'Unlimited books and Word export. Thank you',
            )),
          );
        }
        return ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(tr(zh: '解锁 Pro（一次买断）', en: 'Unlock Pro (one-time purchase)')),
          subtitle: Text(tr(
            zh: '不限项目数 + Word（.docx）导出',
            en: 'Unlimited books + Word (.docx) export',
          )),
          // The store's own localized price, so nobody is quoted a currency
          // they will not be charged in.
          trailing: FilledButton.tonal(
            onPressed: () => showProSheet(context),
            child: const ProPriceText(fallback: r'$9.99'),
          ),
          onTap: () => showProSheet(context),
        );
      },
    );
  }
}
