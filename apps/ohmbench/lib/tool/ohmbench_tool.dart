import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'pro.dart';
import 'store.dart';
import 'tool_module.dart';
import 'ui/home_screen.dart';

/// OhmBench — an offline circuit simulator you can actually edit on a phone.
class OhmBenchTool extends ToolModule {
  OhmBenchTool();

  final ProjectStore store = ProjectStore();

  @override
  Widget buildHome(BuildContext context) => HomeScreen(store: store);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        _ProTile(store: store),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => RestorePurchasesTile(pro: store.pro),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.memory_outlined),
            title: Text(tr(zh: '这台设备上的电路', en: 'On this device')),
            subtitle: Text(tr(
              zh: '${store.projects.length} 张电路图 · 每一步自动保存 · 不联网',
              en: '${store.projects.length} circuits · every step saved · no network',
            )),
          ),
        ),
      ];
}

class _ProTile extends StatelessWidget {
  const _ProTile({required this.store});

  final ProjectStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.pro) {
          return ListTile(
            leading: const Icon(Icons.verified, color: Colors.amber),
            title: Text(tr(zh: '已解锁 Pro', en: 'Pro unlocked')),
            subtitle: Text(tr(
              zh: '不限元件 · 不限电路数 · 感谢支持',
              en: 'Unlimited parts · unlimited circuits · thank you',
            )),
          );
        }
        return ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(tr(zh: '解锁 Pro(一次买断)', en: 'Unlock Pro (one-time purchase)')),
          subtitle: Text(tr(
            zh: '不限元件数 + 不限电路数',
            en: 'Unlimited parts + unlimited circuits',
          )),
          trailing: FilledButton.tonal(
            onPressed: () => showProSheet(context),
            child: const ProPriceText(fallback: r'$4.99'),
          ),
          onTap: () => showProSheet(context),
        );
      },
    );
  }
}
