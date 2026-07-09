import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';
import 'study_screen.dart';

/// Shows one deck's cards, lets the user add/edit/delete them, and starts a
/// review session for the cards that are due today.
class DeckDetailScreen extends StatelessWidget {
  const DeckDetailScreen({super.key, required this.store, required this.deck});

  final RemcardStore store;
  final Deck deck;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final today = epochDayOf(DateTime.now());
        final due = deck.dueCount(today);
        return Scaffold(
          appBar: AppBar(title: Text(deck.name)),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: due > 0
                        ? () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  StudyScreen(store: store, deck: deck),
                            ))
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(due > 0 ? '开始复习($due 张到期)' : '今日已复习完'),
                  ),
                ),
              ),
              Expanded(
                child: deck.cards.isEmpty
                    ? const _NoCards()
                    : ListView.builder(
                        itemCount: deck.cards.length,
                        itemBuilder: (context, i) {
                          final card = deck.cards[i];
                          return Dismissible(
                            key: ValueKey(card.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete,
                                  color: Colors.white),
                            ),
                            onDismissed: (_) => store.deleteCard(deck, card),
                            child: ListTile(
                              title: Text(card.front,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(card.back,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              trailing: card.isDue(today)
                                  ? const Icon(Icons.schedule, size: 18)
                                  : null,
                              onTap: () => _editCard(context, card),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addCard(context),
            icon: const Icon(Icons.add),
            label: const Text('加卡片'),
          ),
        );
      },
    );
  }

  Future<void> _addCard(BuildContext context) async {
    final result = await _cardEditor(context, title: '新建卡片');
    if (result != null) {
      store.addCard(deck, result.$1, result.$2);
    }
  }

  Future<void> _editCard(BuildContext context, Flashcard card) async {
    final result = await _cardEditor(context,
        title: '编辑卡片', front: card.front, back: card.back);
    if (result != null) {
      store.updateCard(card, result.$1, result.$2);
    }
  }
}

class _NoCards extends StatelessWidget {
  const _NoCards();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.note_add_outlined,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            const Text('这个牌组还没有卡片\n点右下角加一张吧',
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Editor dialog returning (front, back) or null if cancelled / empty.
Future<(String, String)?> _cardEditor(
  BuildContext context, {
  required String title,
  String front = '',
  String back = '',
}) {
  final frontCtrl = TextEditingController(text: front);
  final backCtrl = TextEditingController(text: back);
  return showDialog<(String, String)>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: frontCtrl,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: '正面(问题)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: backCtrl,
              minLines: 1,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: '背面(答案)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final f = frontCtrl.text.trim();
            final b = backCtrl.text.trim();
            if (f.isEmpty || b.isEmpty) {
              Navigator.pop(ctx);
            } else {
              Navigator.pop(ctx, (f, b));
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}
