import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'event_detail.dart';
import 'event_edit.dart';
import 'models.dart';
import 'store.dart';
import 'tool_module.dart';
import 'widget_bridge.dart';

/// 倒数日 — offline countdown & anniversary tracker.
class DaycountTool extends ToolModule {
  final EventStore store = EventStore()..load();

  @override
  Widget buildHome(BuildContext context) => _HomeBody(store: store);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        _ProTile(store: store),
        ListTile(
          leading: const Icon(Icons.widgets_outlined),
          title: Text(tr(zh: '刷新桌面小组件', en: 'Refresh home-screen widget')),
          subtitle: Text(tr(zh: '把最近的日子同步到主屏小组件', en: 'Sync the nearest day to the widget')),
          onTap: () async {
            await WidgetBridge.push(store.events);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr(zh: '已刷新小组件', en: 'Widget refreshed'))),
              );
            }
          },
        ),
      ];
}

class _ProTile extends StatelessWidget {
  const _ProTile({required this.store});
  final EventStore store;

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
              zh: '无限日子 · 全部主题色 · 感谢支持',
              en: 'Unlimited days · All theme colors · Thank you',
            )),
          );
        }
        return ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(tr(zh: '解锁 Pro（一次买断）', en: 'Unlock Pro (one-time purchase)')),
          subtitle: Text(tr(zh: '无限日子 + 全部主题色', en: 'Unlimited days + all theme colors')),
          trailing: FilledButton(
            onPressed: () => _confirmUnlock(context),
            child: Text(tr(zh: '解锁', en: 'Unlock')),
          ),
          onTap: () => _confirmUnlock(context),
        );
      },
    );
  }

  void _confirmUnlock(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(zh: '解锁 Pro', en: 'Unlock Pro')),
        content: Text(tr(
          zh: '解锁后可添加无限数量的日子，并使用全部主题色。'
              '（内购接入前为本地解锁占位）',
          en: 'Unlock to add unlimited days and use all theme colors. '
              '(Local unlock placeholder until in-app purchase lands.)',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              store.unlockPro();
              Navigator.pop(context);
            },
            child: Text(tr(zh: '确认解锁', en: 'Unlock now')),
          ),
        ],
      ),
    );
  }
}

class _HomeBody extends StatefulWidget {
  const _HomeBody({required this.store});
  final EventStore store;

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  EventStore get store => widget.store;

  Future<void> _addEvent() async {
    if (store.atLimit) {
      _showLimitDialog();
      return;
    }
    final draft = await Navigator.of(context).push<EventDraft>(
      MaterialPageRoute(builder: (_) => EventEditPage(pro: store.pro)),
    );
    if (draft != null) {
      store.add(
        title: draft.title,
        date: draft.date,
        emoji: draft.emoji,
        colorValue: draft.colorValue,
        pinned: draft.pinned,
        yearlyRepeat: draft.yearlyRepeat,
        note: draft.note,
      );
    }
  }

  void _showLimitDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(zh: '已达免费上限', en: 'Free limit reached')),
        content: Text(tr(
          zh: '免费版最多记录 ${EventStore.freeLimit} 个日子。解锁 Pro 可添加无限数量。',
          en: 'The free version keeps up to ${EventStore.freeLimit} days. Unlock Pro for unlimited days.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(zh: '知道了', en: 'Got it')),
          ),
          FilledButton(
            onPressed: () {
              store.unlockPro();
              Navigator.pop(context);
            },
            child: Text(tr(zh: '解锁 Pro', en: 'Unlock Pro')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (!store.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = sortedEvents(store.events, DateTime.now());
          if (items.isEmpty) return const _EmptyState();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: items.length,
            itemBuilder: (context, i) => _EventCard(
              event: items[i],
              store: store,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEvent,
        icon: const Icon(Icons.add),
        label: Text(tr(zh: '添加日子', en: 'Add a day')),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available_outlined, size: 72, color: muted),
            const SizedBox(height: 16),
            Text(tr(zh: '还没有日子', en: 'No days yet'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              tr(
                zh: '点击右下角「添加日子」，记录生日、纪念日、\n考试倒计时……并放上桌面小组件。',
                en: 'Tap "Add a day" to track birthdays, anniversaries,\nexam countdowns… and put them on your widget.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.store});
  final CountdownEvent event;
  final EventStore store;

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

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailPage(store: store, eventId: event.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(event.emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (event.pinned)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.push_pin, size: 15, color: Colors.grey),
                          ),
                        Expanded(
                          child: Text(
                            event.title.isEmpty ? tr(zh: '未命名', en: 'Untitled') : event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.target.year}-${_two(s.target.month)}-${_two(s.target.day)} ${weekdayLabel(s.target)}'
                      '${event.yearlyRepeat ? ' · ${tr(zh: '每年', en: 'yearly')}' : ''}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _DayBadge(label: label, status: s, bg: color, fg: onColor),
            ],
          ),
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class _DayBadge extends StatelessWidget {
  const _DayBadge({
    required this.label,
    required this.status,
    required this.bg,
    required this.fg,
  });
  final String label;
  final EventStatus status;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 68),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.9))),
          const SizedBox(height: 1),
          Text(
            status.isToday ? '🎉' : '${status.absDays}',
            style: TextStyle(
              fontSize: 24,
              height: 1.05,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          if (!status.isToday)
            Text(tr(zh: '天', en: 'days'),
                style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.9))),
        ],
      ),
    );
  }
}
