import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'home_page.dart';
import 'note.dart';
import 'tool_module.dart';

class EchoJotTool extends ToolModule {
  @override
  Widget buildHome(BuildContext context) => const EchoJotHome();

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        ListTile(
          leading: const Icon(Icons.ios_share_outlined),
          title: const Text('导出全部笔记'),
          subtitle: const Text('合并为一段文本,通过分享面板导出'),
          onTap: () async {
            final store = await NoteStore.open();
            final all = store.notes
                .map((n) =>
                    '## ${n.title}\n${n.createdAt.toLocal()}\n\n${n.text}')
                .join('\n\n---\n\n');
            await SharePlus.instance.share(
              ShareParams(text: all.isEmpty ? '(还没有笔记)' : all),
            );
          },
        ),
        const ListTile(
          leading: Icon(Icons.wifi_off_outlined),
          title: Text('零网络承诺'),
          subtitle: Text('本 app 未申请任何网络权限,录音与文字永远只在本机。'),
        ),
      ];
}
