import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';

/// A review session over the cards that were due when the session started.
/// Tap the card to reveal the answer, then grade it; grading reschedules the
/// card and advances to the next one.
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.store, required this.deck});

  final RemcardStore store;
  final Deck deck;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  late final List<Flashcard> _queue;
  int _index = 0;
  bool _revealed = false;
  int _reviewed = 0;

  @override
  void initState() {
    super.initState();
    final today = epochDayOf(DateTime.now());
    // Snapshot the due set at session start so rescheduled cards don't reappear.
    _queue = widget.deck.dueCards(today);
  }

  void _grade(Rating rating) {
    widget.store.reviewCard(_queue[_index], rating);
    setState(() {
      _reviewed += 1;
      _index += 1;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= _queue.length) {
      return _DoneScreen(reviewed: _reviewed);
    }
    final card = _queue[_index];
    final remaining = _queue.length - _index;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('复习 · 剩 $remaining 张'),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: _queue.isEmpty ? 1 : _index / _queue.length,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _revealed = true),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          card.front,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (_revealed) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Divider(),
                          ),
                          Text(
                            card.back,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: scheme.primary),
                          ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Text('点击显示答案',
                                style: TextStyle(color: scheme.outline)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _revealed
                  ? Row(
                      children: [
                        for (final r in Rating.values)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: FilledButton.tonal(
                                onPressed: () => _grade(r),
                                child: Text(r.label),
                              ),
                            ),
                          ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => setState(() => _revealed = true),
                        child: const Text('显示答案'),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneScreen extends StatelessWidget {
  const _DoneScreen({required this.reviewed});

  final int reviewed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('复习完成')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.celebration_outlined,
                size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('本轮复习了 $reviewed 张',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}
