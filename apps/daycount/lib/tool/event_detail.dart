import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'event_edit.dart';
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
    final s = statusOf(event, DateTime.now());
    final color = event.color;
    final onColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final label = s.isToday
        ? tr(zh: '就是今天', en: 'Today!')
        : (s.isFuture ? tr(zh: '还有', en: 'in') : tr(zh: '已过去', en: 'past'));

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
              color: color,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Text(event.emoji, style: const TextStyle(fontSize: 44)),
                const SizedBox(height: 8),
                Text(
                  event.title.isEmpty ? tr(zh: '未命名', en: 'Untitled') : event.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: onColor.withValues(alpha: 0.95)),
                ),
                const SizedBox(height: 18),
                Text(label, style: TextStyle(fontSize: 14, color: onColor.withValues(alpha: 0.9))),
                Text(
                  s.isToday ? '🎉' : '${s.absDays}',
                  style: TextStyle(
                    fontSize: 76,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    color: onColor,
                  ),
                ),
                if (!s.isToday)
                  Text(tr(zh: '天', en: 'days'),
                      style: TextStyle(fontSize: 16, color: onColor.withValues(alpha: 0.9))),
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
