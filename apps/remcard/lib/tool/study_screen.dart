import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'models.dart';
import 'store.dart';

/// Localized button labels for the four SM-2 grades (Anki-style terms).
String _ratingLabel(Rating r) => switch (r) {
      Rating.again => tr(zh: '重来', en: 'Again'),
      Rating.hard => tr(zh: '困难', en: 'Hard'),
      Rating.good => tr(zh: '良好', en: 'Good'),
      Rating.easy => tr(zh: '简单', en: 'Easy'),
    };

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
        title: Text(tr(
          zh: '复习 · 剩 $remaining 张',
          en: 'Review · $remaining left',
        )),
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
                            child: Text(
                                tr(zh: '点击显示答案', en: 'Tap to show answer'),
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
                                child: Text(_ratingLabel(r)),
                              ),
                            ),
                          ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => setState(() => _revealed = true),
                        child: Text(tr(zh: '显示答案', en: 'Show answer')),
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
      appBar: AppBar(title: Text(tr(zh: '复习完成', en: 'Review done'))),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.celebration_outlined,
                size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
                tr(
                  zh: '本轮复习了 $reviewed 张',
                  en: reviewed == 1
                      ? 'Reviewed 1 card this session'
                      : 'Reviewed $reviewed cards this session',
                ),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(zh: '返回', en: 'Back')),
            ),
          ],
        ),
      ),
    );
  }
}
