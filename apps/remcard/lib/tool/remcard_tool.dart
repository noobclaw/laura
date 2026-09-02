import 'package:flutter/material.dart';

import '../core/day_change.dart';
import '../core/l10n.dart';
import '../core/purchase.dart';
import 'deck_detail.dart';
import 'import_flow.dart';
import 'models.dart';
import 'store.dart';
import 'tool_module.dart';

/// Remcard: offline spaced-repetition flashcards. Everything the shell needs
/// is behind [ToolModule]; the store is created once and shared across screens.
class RemcardTool extends ToolModule {
  RemcardTool() {
    store.load();
    dayChange.start();
  }

  final RemcardStore store = RemcardStore();

  /// Re-derives "due today" at midnight and when the app comes back to the
  /// foreground on a new day — otherwise an app left open overnight keeps
  /// saying "all caught up" about yesterday.
  final DayChangeNotifier dayChange = DayChangeNotifier();

  @override
  Widget buildHome(BuildContext context) =>
      DeckListScreen(store: store, dayChange: dayChange);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        ListTile(
          leading: const Icon(Icons.file_open_outlined),
          title: Text(tr(zh: '导入牌组文件', en: 'Import a deck file')),
          subtitle: Text(tr(
            zh: 'CSV / TSV / Anki 牌组包(.apkg),全部在手机上完成',
            en: 'CSV / TSV / Anki package (.apkg), entirely on this phone',
          )),
          onTap: () => _importGuarded(context, store),
        ),
        ListTile(
          leading: const Icon(Icons.school_outlined),
          title: Text(tr(zh: '间隔重复原理', en: 'How spaced repetition works')),
          subtitle: Text(tr(
            zh: '答对越久不再问,答错很快重来',
            en: 'Correct answers wait longer; misses come back soon',
          )),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const _SrsExplainPage(),
          )),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: Icon(store.pro ? Icons.verified : Icons.lock_open_outlined),
            title: Text(store.pro
                ? tr(zh: 'Pro 已解锁', en: 'Pro unlocked')
                : tr(zh: '解锁 Pro(无限牌组)', en: 'Unlock Pro (unlimited decks)')),
            subtitle: Text(store.pro
                ? tr(zh: '感谢支持', en: 'Thanks for your support')
                : tr(
                    zh: '一次买断 · 免费版 ${RemcardStore.freeDeckLimit} 个牌组,'
                        '卡片数量无限制',
                    en: 'One-time purchase · free version: '
                        '${RemcardStore.freeDeckLimit} decks, unlimited cards',
                  )),
            trailing: store.pro
                ? null
                : FilledButton.tonal(
                    onPressed: () => showPaywall(context),
                    child: const ProPriceText(fallback: r'$4.99'),
                  ),
            onTap: store.pro ? null : () => showPaywall(context),
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => RestorePurchasesTile(pro: store.pro),
        ),
      ];
}

/// The paywall: what Pro adds, the store's real price, one buy button, and
/// the restore path for people who already paid. Reached from every free
/// gate (new deck, import) so hitting the cap never dead-ends in a snackbar.
Future<void> showPaywall(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final text = Theme.of(context).textTheme;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          24, 4, 24, 24 + MediaQuery.of(ctx).viewPadding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.workspace_premium_outlined, size: 44, color: scheme.primary),
          const SizedBox(height: 10),
          Text(
            tr(zh: 'Remcard Pro', en: 'Remcard Pro'),
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            tr(
              zh: '一次买断,永久使用。没有订阅,没有账号,数据永远只在你的手机里。',
              en: 'Pay once, keep it forever. No subscription, no account — '
                  'your data never leaves your phone.',
            ),
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          _Benefit(
            icon: Icons.all_inclusive,
            title: tr(zh: '无限牌组', en: 'Unlimited decks'),
            body: tr(
              zh: '免费版 ${RemcardStore.freeDeckLimit} 个;Pro 不限。卡片数量两者都不限。',
              en: 'Free allows ${RemcardStore.freeDeckLimit}; Pro removes the cap. '
                  'Cards are unlimited either way.',
            ),
          ),
          _Benefit(
            icon: Icons.file_open_outlined,
            title: tr(zh: '导入无限量', en: 'Import without limits'),
            body: tr(
              zh: '把 Anki 共享牌组、CSV 词表直接导进手机,想导几个导几个。',
              en: 'Bring in as many Anki shared decks and CSV lists as you like.',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () {
              Navigator.pop(ctx);
              PurchaseService.instance.buyPro();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(tr(zh: '解锁 Pro · ', en: 'Unlock Pro · ')),
                const ProPriceText(fallback: r'$4.99'),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              PurchaseService.instance.restore();
            },
            child: Text(tr(zh: '已经买过?恢复购买', en: 'Already paid? Restore')),
          ),
        ],
      ),
    ),
  );
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                Text(body,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Import honours the same free-tier deck cap as "New deck": the picker is
/// never even opened when a new deck could not be created.
Future<void> _importGuarded(BuildContext context, RemcardStore store) async {
  if (store.atDeckLimit) {
    await showPaywall(context);
    return;
  }
  await runImportFlow(context, store);
}

class DeckListScreen extends StatelessWidget {
  const DeckListScreen({super.key, required this.store, this.dayChange});

  final RemcardStore store;
  final Listenable? dayChange;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dayChange == null
          ? store
          : Listenable.merge([store, dayChange!]),
      builder: (context, _) {
        if (!store.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final today = epochDayOf(DateTime.now());
        final totalDue =
            store.decks.fold<int>(0, (sum, d) => sum + d.dueCount(today));
        return Scaffold(
          body: store.decks.isEmpty
              ? _EmptyState(
                  onCreate: () => _createDeck(context),
                  onImport: () => _importGuarded(context, store),
                )
              : ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 96),
                  children: [
                    _DueTodayHero(totalDue: totalDue),
                    _ImportRow(onImport: () => _importGuarded(context, store)),
                    for (final deck in store.decks)
                      _DeckTile(
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
                      ),
                  ],
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _createDeck(context),
            icon: const Icon(Icons.add),
            label: Text(tr(zh: '新建牌组', en: 'New deck')),
          ),
        );
      },
    );
  }

  Future<void> _createDeck(BuildContext context) async {
    if (store.atDeckLimit) {
      await showPaywall(context);
      return;
    }
    final name =
        await _promptName(context, title: tr(zh: '新建牌组', en: 'New deck'));
    if (name != null && name.trim().isNotEmpty) {
      store.addDeck(name);
    }
  }

  Future<void> _renameDeck(BuildContext context, Deck deck) async {
    final name = await _promptName(context,
        title: tr(zh: '重命名牌组', en: 'Rename deck'), initial: deck.name);
    if (name != null && name.trim().isNotEmpty) {
      store.renameDeck(deck, name);
    }
  }

  Future<void> _deleteDeck(BuildContext context, Deck deck) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(
          zh: '删除「${deck.name}」?',
          en: 'Delete "${deck.name}"?',
        )),
        content: Text(tr(
          zh: '将删除牌组内 ${deck.cards.length} 张卡片,不可恢复。',
          en: 'This deletes the ${deck.cards.length} card(s) in this deck. '
              'This cannot be undone.',
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(zh: '取消', en: 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(zh: '删除', en: 'Delete')),
          ),
        ],
      ),
    );
    if (ok == true) store.deleteDeck(deck);
  }

}

/// One quiet, full-width tonal button under the hero: the deck list is where
/// people look for "how do I get my Anki decks in here", so the answer sits
/// right there instead of only in Settings.
class _ImportRow extends StatelessWidget {
  const _ImportRow({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: onImport,
          icon: const Icon(Icons.file_open_outlined),
          label: Text(tr(
            zh: '从 CSV / Anki 牌组导入',
            en: 'Import from CSV / Anki deck',
          )),
        ),
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
        decoration: InputDecoration(
          hintText: tr(zh: '牌组名称', en: 'Deck name'),
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(zh: '取消', en: 'Cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(tr(zh: '确定', en: 'OK'))),
      ],
    ),
  );
}

/// A compact teal hero at the top of the deck list: the total cards due today,
/// as a big tabular number over a gradient `primaryContainer`, with a short
/// label (and a reassuring note once you're caught up).
class _DueTodayHero extends StatelessWidget {
  const _DueTodayHero({required this.totalDue});

  final int totalDue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final caughtUp = totalDue == 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primaryContainer,
                Color.alphaBlend(
                  scheme.primary.withValues(alpha: 0.30),
                  scheme.primaryContainer,
                ),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -18,
                child: Icon(
                  Icons.style_rounded,
                  size: 132,
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.08),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$totalDue',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                            height: 1.0,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      caughtUp
                          ? tr(zh: '今日已全部复习完 🎉', en: 'All caught up for today 🎉')
                          : tr(zh: '今日待复习卡片', en: 'cards due to review today'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color:
                                scheme.onPrimaryContainer.withValues(alpha: 0.85),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    final total = deck.cards.length;
    // Fraction of the deck that has entered the schedule (been reviewed at
    // least once) — a quiet sense of progress per deck.
    final reviewed = deck.cards.where((c) => c.repetitions > 0).length;
    final progress = total == 0 ? 0.0 : reviewed / total;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onOpen,
        title: Text(deck.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(
              zh: '$total 张卡片',
              en: total == 1 ? '1 card' : '$total cards',
            )),
            if (total > 0) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
          ],
        ),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor:
              due > 0 ? scheme.primary : scheme.surfaceContainerHighest,
          foregroundColor:
              due > 0 ? scheme.onPrimary : scheme.onSurfaceVariant,
          child: Text(
            '$due',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'rename') onRename();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
                value: 'rename', child: Text(tr(zh: '重命名', en: 'Rename'))),
            PopupMenuItem(
                value: 'delete', child: Text(tr(zh: '删除', en: 'Delete'))),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate, required this.onImport});

  final VoidCallback onCreate;
  final VoidCallback onImport;

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
            Text(tr(zh: '还没有牌组', en: 'No decks yet'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              tr(
                zh: '新建一个牌组,加入卡片,\nRemcard 会按记忆规律安排你复习。',
                en: 'Create a deck and add cards.\n'
                    'Remcard schedules your reviews for you.',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(tr(zh: '新建第一个牌组', en: 'Create your first deck')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(tr(
                zh: '导入 CSV / Anki 牌组',
                en: 'Import CSV / Anki deck',
              )),
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                zh: '已有 Anki 牌组?直接在手机上导入,不用电脑。',
                en: 'Already have Anki decks? Import them right here — '
                    'no desktop needed.',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
    final body = tr(
      zh: '''
Remcard 使用经典的 SM-2 间隔重复算法安排复习。

复习一张卡片后,你会给出 4 档评价:
• 重来 — 没记住,明天再问一次,并重置记忆进度。
• 困难 — 勉强想起,间隔小幅增加。
• 良好 — 顺利答对,间隔按正常节奏拉长。
• 简单 — 秒答,间隔拉得更长,以后更久才会再出现。

新卡片首次复习后隔 1 天,再对隔 6 天,之后每次乘以一个「熟练度系数」(会随你的表现在 1.3 以上浮动)。答错则回到 1 天重新学起。

这样你只会在「快要忘记」时复习,用最少的次数记得最牢——而且全部计算都在这台手机上完成,不联网。
''',
      en: '''
Remcard schedules reviews with the classic SM-2 spaced-repetition algorithm.

After reviewing a card, you grade it on four levels:
• Again — you forgot; the card comes back tomorrow and its progress resets.
• Hard — barely recalled; the interval grows a little.
• Good — recalled correctly; the interval grows at the normal pace.
• Easy — instant recall; the interval grows even more, so the card waits longer.

A new card comes back after 1 day, then 6 days, and after that each interval is multiplied by an "ease factor" that floats above 1.3 based on your performance. A miss sends the card back to 1 day.

This way you only review a card right before you would forget it — the fewest reviews for the strongest memory. And every calculation happens on this phone, offline.
''',
    );
    return Scaffold(
      appBar: AppBar(
          title:
              Text(tr(zh: '间隔重复原理', en: 'How spaced repetition works'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(body, style: const TextStyle(height: 1.5)),
      ),
    );
  }
}
