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

/// Distinct (background, foreground) per grade so the four buttons read at a
/// glance: Again=error, Hard=tertiary, Good=primary (the brand teal), Easy=
/// secondary — the tonal container roles keep them coherent with the theme.
(Color, Color) _ratingColors(ColorScheme s, Rating r) => switch (r) {
      Rating.again => (s.errorContainer, s.onErrorContainer),
      Rating.hard => (s.tertiaryContainer, s.onTertiaryContainer),
      Rating.good => (s.primaryContainer, s.onPrimaryContainer),
      Rating.easy => (s.secondaryContainer, s.onSecondaryContainer),
    };

/// A review session over the cards that were due when the session started.
/// Tap the card to reveal the answer, then grade it; grading reschedules the
/// card and advances to the next one.
///
/// "Again" puts the card back at the end of this session's queue (the SM-2
/// paper's "repeat until every item scores ≥ 4", and what Anki users
/// expect): a missed card is not gone until you have actually recalled it.
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.store, required this.deck});

  final RemcardStore store;
  final Deck deck;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  late final List<Flashcard> _queue;
  final Set<String> _seen = {};
  int _index = 0;
  bool _revealed = false;
  int _lapses = 0;

  @override
  void initState() {
    super.initState();
    final today = epochDayOf(DateTime.now());
    // Snapshot the due set at session start so rescheduled cards don't reappear.
    _queue = List.of(widget.deck.dueCards(today));
  }

  void _grade(Rating rating) {
    final card = _queue[_index];
    final repeat = _seen.contains(card.id);
    if (repeat) {
      // Already lapsed this session: the relearn grade only sets when it
      // comes back, it must not dock ease again.
      widget.store.relearnCard(card, rating);
    } else {
      widget.store.reviewCard(card, rating);
    }
    setState(() {
      _seen.add(card.id);
      if (rating == Rating.again) {
        if (!repeat) _lapses += 1;
        _queue.add(card);
      }
      _index += 1;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= _queue.length) {
      return _DoneScreen(reviewed: _seen.length, lapses: _lapses);
    }
    final card = _queue[_index];
    final remaining = _queue.length - _index;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isRepeat = _seen.contains(card.id);

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
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Center(
                  child: _CardFace(
                    front: card.front,
                    back: _revealed ? card.back : null,
                    repeat: isRepeat,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: _revealed
                  ? Row(
                      children: [
                        for (final r in Rating.values)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Builder(builder: (context) {
                                final (bg, fg) = _ratingColors(scheme, r);
                                // The number under each label is the card's
                                // next interval for that grade — what the
                                // user is actually choosing between.
                                final days = isRepeat
                                    ? card.previewRelearnInterval(r)
                                    : card.previewInterval(r);
                                return FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: bg,
                                    foregroundColor: fg,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                  onPressed: () => _grade(r),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(_ratingLabel(r),
                                          style: text.labelLarge
                                              ?.copyWith(color: fg)),
                                      const SizedBox(height: 2),
                                      Text(
                                        r == Rating.again
                                            ? tr(zh: '稍后再出', en: 'again soon')
                                            : intervalLabel(days),
                                        style: text.labelSmall?.copyWith(
                                          color: fg.withValues(alpha: 0.8),
                                          fontFeatures: const [
                                            FontFeature.tabularFigures()
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16)),
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

/// The card itself: a raised tonal surface with the question, and — once
/// revealed — a rule and the answer in the brand colour. It is the one thing
/// on screen, so it gets real presence instead of floating text.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.front, this.back, required this.repeat});

  final String front;
  final String? back;
  final bool repeat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (repeat)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tr(zh: '再试一次', en: 'Try again'),
                      style: text.labelSmall
                          ?.copyWith(color: scheme.onErrorContainer),
                    ),
                  ),
                ),
              Text(
                front,
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(height: 1.3),
              ),
              if (back != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Divider(color: scheme.outlineVariant),
                ),
                Text(
                  back!,
                  textAlign: TextAlign.center,
                  style: text.titleLarge
                      ?.copyWith(color: scheme.primary, height: 1.35),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 26),
                  child: Text(
                    tr(zh: '点击显示答案', en: 'Tap to show answer'),
                    style: text.bodyMedium?.copyWith(color: scheme.outline),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneScreen extends StatelessWidget {
  const _DoneScreen({required this.reviewed, required this.lapses});

  final int reviewed;
  final int lapses;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '复习完成', en: 'Review done'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.celebration_outlined, size: 72, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                tr(
                  zh: '本轮复习了 $reviewed 张',
                  en: reviewed == 1
                      ? 'Reviewed 1 card this session'
                      : 'Reviewed $reviewed cards this session',
                ),
                style: text.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                lapses == 0
                    ? tr(zh: '全部一次记住,漂亮。', en: 'All recalled first time. Nice.')
                    : tr(
                        zh: '$lapses 次「重来」已当场补练,明天再来一遍。',
                        en: lapses == 1
                            ? '1 miss was practised again on the spot; it comes back tomorrow.'
                            : '$lapses misses were practised again on the spot; they come back tomorrow.',
                      ),
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(tr(zh: '返回', en: 'Back')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
