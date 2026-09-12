import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/review_prompt.dart';
import 'accent_ink.dart';
import 'event_edit.dart';
import 'hero_card.dart';
import 'models.dart';
import 'store.dart';

class EventDetailPage extends StatelessWidget {
  const EventDetailPage({super.key, required this.store, required this.eventId});

  final EventStore store;
  final String eventId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final event = store.events.where((e) => e.id == eventId).firstOrNull;
        if (event == null) {
          // Deleted while open — pop back to the list.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
          return const Scaffold();
        }
        return _DetailView(store: store, event: event);
      },
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView({required this.store, required this.event});
  final EventStore store;
  final CountdownEvent event;

  Future<void> _edit(BuildContext context) async {
    final draft = await Navigator.of(context).push<EventDraft>(
      MaterialPageRoute(
        builder: (_) => EventEditPage(initial: event, pro: store.pro),
      ),
    );
    if (draft != null) {
      event.title = draft.title;
      event.date = draft.date;
      event.emoji = draft.emoji;
      event.colorValue = draft.colorValue;
      event.pinned = draft.pinned;
      event.yearlyRepeat = draft.yearlyRepeat;
      event.note = draft.note;
      store.update(event);
      // Core action for the store-rating prompt (PLAN.md G8b-7): a day saved.
      unawaited(ReviewPrompt.noteCoreAction());
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(zh: '删除这个日子？', en: 'Delete this day?')),
        content: Text(tr(
          zh: '「${event.title}」将被删除，无法恢复。',
          en: '"${event.title}" will be deleted. This cannot be undone.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(zh: '删除', en: 'Delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      store.delete(event);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final s = statusOf(event, now);
    final progress = progressOf(event, now);
    final color = event.color;
    final ink = onColorFor(color);
    final onColor = ink.fg;
    final label = s.isToday
        ? tr(zh: '就是今天', en: 'Today!')
        : (s.isFuture ? tr(zh: '还有', en: 'in') : tr(zh: '已过去', en: 'past'));
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(event.title.isEmpty ? tr(zh: '日子', en: 'Day') : event.title),
        actions: [
          IconButton(
            tooltip: event.pinned ? tr(zh: '取消置顶', en: 'Unpin') : tr(zh: '置顶', en: 'Pin'),
            icon: Icon(event.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: () => store.togglePin(event),
          ),
          IconButton(
            tooltip: tr(zh: '编辑', en: 'Edit'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _edit(context),
          ),
          IconButton(
            tooltip: tr(zh: '删除', en: 'Delete'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, Color.lerp(color, Colors.black, 0.32)!],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                // Shared with the home list / hero card: the emoji flies
                // between the two screens.
                Hero(
                  tag: emojiHeroTag(event),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Text(event.emoji, style: const TextStyle(fontSize: 44)),
                  ),
                ),
                const SizedBox(height: 8),
                // 20px semibold is WCAG "large" text, so it may sit straight
                // on the accent; the small labels below go on a chip.
                Text(
                  event.title.isEmpty ? tr(zh: '未命名', en: 'Untitled') : event.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: onColor,
                  ),
                ),
                const SizedBox(height: 18),
                _Chip(text: label, fg: onColor, bg: ink.chip),
                const SizedBox(height: 8),
                SizedBox(
                  width: 172,
                  height: 172,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (progress != null)
                        SizedBox(
                          width: 172,
                          height: 172,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: progress),
                            duration: reduce
                                ? Duration.zero
                                : const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => CircularProgressIndicator(
                              value: v,
                              strokeWidth: 6,
                              strokeCap: StrokeCap.round,
                              backgroundColor: onColor.withValues(alpha: 0.2),
                              valueColor: AlwaysStoppedAnimation(onColor.withValues(alpha: 0.9)),
                            ),
                          ),
                        ),
                      // Shrinks to fit inside the ring: 10,000+ days (a 27-year
                      // anniversary) used to lose its last digit to the clip.
                      SizedBox(
                        width: 140,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: s.isToday
                              ? Text(
                                  '🎉',
                                  style: TextStyle(fontSize: 76, height: 1.05, color: onColor),
                                )
                              // Rolls up to the value instead of snapping in.
                              : TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: s.absDays.toDouble()),
                                  duration: reduce
                                      ? Duration.zero
                                      : const Duration(milliseconds: 800),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, v, _) => Text(
                                    '${v.round()}',
                                    style: TextStyle(
                                      fontSize: 76,
                                      height: 1.05,
                                      fontWeight: FontWeight.w800,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                      color: onColor,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!s.isToday)
                  _Chip(text: tr(zh: '天', en: 'days'), fg: onColor, bg: ink.chip),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _InfoRow(
            icon: Icons.event,
            label: tr(zh: '目标日期', en: 'Date'),
            value: '${s.target.year}-${_two(s.target.month)}-${_two(s.target.day)} ${weekdayLabel(s.target)}',
          ),
          if (event.yearlyRepeat)
            _InfoRow(
              icon: Icons.repeat,
              label: tr(zh: '重复', en: 'Repeat'),
              value: tr(zh: '每年', en: 'Yearly'),
            ),
          _InfoRow(
            icon: Icons.today_outlined,
            label: tr(zh: '距今', en: 'From today'),
            value: s.isToday
                ? tr(zh: '就是今天', en: 'Today!')
                : (s.isFuture
                    ? tr(zh: '还有 ${s.absDays} 天', en: 'in ${s.absDays} days')
                    : tr(zh: '已过去 ${s.absDays} 天', en: '${s.absDays} days ago')),
          ),
          if (event.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(icon: Icons.notes_outlined, label: tr(zh: '备注', en: 'Note'), value: event.note),
          ],
        ],
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// Small text on the accent card: sits on the dark band (or a light wash on a
/// light accent) so it clears WCAG AA where the accent itself would not.
class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.fg, required this.bg});
  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: 14),
          SizedBox(
            width: 64,
            child: Text(label, style: TextStyle(color: muted)),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
