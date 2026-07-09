import 'package:flutter/material.dart';

import 'deck_detail.dart';
import 'models.dart';
import 'store.dart';
import 'tool_module.dart';

/// Remcard: offline spaced-repetition flashcards. Everything the shell needs
/// is behind [ToolModule]; the store is created once and shared across screens.
class RemcardTool extends ToolModule {
  RemcardTool() {
    store.load();
  }

  final RemcardStore store = RemcardStore();

  @override
  Widget buildHome(BuildContext context) => DeckListScreen(store: store);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        ListTile(
          leading: const Icon(Icons.school_outlined),
          title: const Text('间隔重复原理'),
          subtitle: const Text('答对越久不再问,答错很快重来'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const _SrsExplainPage(),
          )),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: Icon(store.pro ? Icons.verified : Icons.lock_open_outlined),
            title: Text(store.pro ? 'Pro 已解锁' : '解锁 Pro(无限牌组)'),
            subtitle: Text(store.pro
                ? '感谢支持'
                : '免费版 ${RemcardStore.freeDeckLimit} 个牌组;卡片数量无限制'),
            onTap: store.pro ? null : () => _confirmUnlock(context),
          ),
        ),
      ];

  void _confirmUnlock(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解锁 Pro'),
        content: const Text(
          '一次性买断,解锁无限牌组。\n\n'
          '(正式版将接入应用内购买;当前为本地占位开关。)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              store.unlockPro();
              Navigator.pop(ctx);
            },
            child: const Text('解锁'),
          ),
        ],
      ),
    );
  }
}

class DeckListScreen extends StatelessWidget {
  const DeckListScreen({super.key, required this.store});

  final RemcardStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final today = epochDayOf(DateTime.now());
        return Scaffold(
          body: store.decks.isEmpty
              ? _EmptyState(onCreate: () => _createDeck(context))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: store.decks.length,
                  itemBuilder: (context, i) {
                    final deck = store.decks[i];
                    return _DeckTile(
                      deck: deck,
                      today: today,
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DeckDetailScreen(store: store, deck: deck),
                        ),
                      ),
                      onRename: () => _renameDeck(context, deck),
                      onDelete: () => _deleteDeck(context, deck),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _createDeck(context),
            icon: const Icon(Icons.add),
            label: const Text('新建牌组'),
          ),
        );
      },
    );
  }

  Future<void> _createDeck(BuildContext context) async {
    if (store.atDeckLimit) {
      _showLimit(context);
      return;
    }
    final name = await _promptName(context, title: '新建牌组');
    if (name != null && name.trim().isNotEmpty) {
      store.addDeck(name);
    }
  }

  Future<void> _renameDeck(BuildContext context, Deck deck) async {
    final name =
        await _promptName(context, title: '重命名牌组', initial: deck.name);
    if (name != null && name.trim().isNotEmpty) {
      store.renameDeck(deck, name);
    }
  }

  Future<void> _deleteDeck(BuildContext context, Deck deck) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${deck.name}」?'),
        content: Text('将删除牌组内 ${deck.cards.length} 张卡片,不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) store.deleteDeck(deck);
  }

  void _showLimit(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('免费版最多 ${RemcardStore.freeDeckLimit} 个牌组,'
            '在设置里解锁 Pro 以创建更多。'),
      ),
    );
  }
}

Future<String?> _promptName(BuildContext context,
    {required String title, String? initial}) {
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: '牌组名称',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('确定')),
      ],
    ),
  );
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({
    required this.deck,
    required this.today,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final Deck deck;
  final int today;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final due = deck.dueCount(today);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onOpen,
        title: Text(deck.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${deck.cards.length} 张卡片'),
        leading: CircleAvatar(
          backgroundColor: due > 0 ? scheme.primary : scheme.surfaceContainerHighest,
          foregroundColor: due > 0 ? scheme.onPrimary : scheme.onSurfaceVariant,
          child: Text('$due'),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'rename') onRename();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('重命名')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style_outlined,
                size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('还没有牌组',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              '新建一个牌组,加入卡片,\nRemcard 会按记忆规律安排你复习。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('新建第一个牌组'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SrsExplainPage extends StatelessWidget {
  const _SrsExplainPage();

  @override
  Widget build(BuildContext context) {
    const body = '''
Remcard 使用经典的 SM-2 间隔重复算法安排复习。

复习一张卡片后,你会给出 4 档评价:
• 重来 — 没记住,明天再问一次,并重置记忆进度。
• 困难 — 勉强想起,间隔小幅增加。
• 良好 — 顺利答对,间隔按正常节奏拉长。
• 简单 — 秒答,间隔拉得更长,以后更久才会再出现。

新卡片首次复习后隔 1 天,再对隔 6 天,之后每次乘以一个「熟练度系数」(会随你的表现在 1.3 以上浮动)。答错则回到 1 天重新学起。

这样你只会在「快要忘记」时复习,用最少的次数记得最牢——而且全部计算都在这台手机上完成,不联网。
''';
    return Scaffold(
      appBar: AppBar(title: const Text('间隔重复原理')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Text(body, style: TextStyle(height: 1.5)),
      ),
    );
  }
}
