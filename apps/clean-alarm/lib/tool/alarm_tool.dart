import 'dart:async';

import 'package:flutter/material.dart';

import 'alarm_edit.dart';
import 'models.dart';
import 'scheduler.dart';
import 'store.dart';
import 'tool_module.dart';

/// Makes the shared [AlarmStore] available to the home body and the pushed
/// settings/edit routes. Placed above MaterialApp in main.dart.
class AlarmScope extends InheritedNotifier<AlarmStore> {
  const AlarmScope({super.key, required AlarmStore store, required super.child})
      : super(notifier: store);

  static AlarmStore of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AlarmScope>();
    assert(scope != null, 'AlarmScope not found in widget tree');
    return scope!.notifier!;
  }
}

class AlarmTool extends ToolModule {
  @override
  Widget buildHome(BuildContext context) => const AlarmListView();

  @override
  List<Widget> buildSettingsItems(BuildContext context) {
    final store = AlarmScope.of(context);
    return [
      if (!store.pro)
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('解锁 Pro'),
          subtitle: const Text('无限闹钟 + 全部主题强调色 · 一次买断'),
          onTap: () {
            store.unlockPro();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已解锁 Pro，谢谢支持！')),
            );
          },
        )
      else
        const ListTile(
          leading: Icon(Icons.workspace_premium, color: Colors.amber),
          title: Text('Pro 已解锁'),
          subtitle: Text('无限闹钟 + 全部主题强调色'),
        ),
      ListTile(
        leading: const Icon(Icons.palette_outlined),
        title: const Text('主题强调色'),
        subtitle: Text(store.pro ? '点击选择' : '解锁 Pro 后可选'),
        trailing: _AccentDots(store: store),
      ),
      ListTile(
        leading: const Icon(Icons.notifications_active_outlined),
        title: const Text('通知与精确闹钟权限'),
        subtitle: const Text('闹钟准时响铃需要授予，点击重新请求'),
        onTap: () => AlarmScheduler.instance.requestPermissions(),
      ),
      const Divider(),
    ];
  }
}

class _AccentDots extends StatelessWidget {
  const _AccentDots({required this.store});
  final AlarmStore store;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < accentPalette.length; i++)
          GestureDetector(
            onTap: () {
              if (!store.pro && i != 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('解锁 Pro 后可用')),
                );
                return;
              }
              store.setAccent(i);
            },
            child: Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: Color(accentPalette[i]),
                shape: BoxShape.circle,
                border: Border.all(
                  color: store.accent == i ? Colors.white : Colors.transparent,
                  width: 2,
                ),
                boxShadow: store.accent == i
                    ? [const BoxShadow(blurRadius: 3, color: Colors.black26)]
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class AlarmListView extends StatefulWidget {
  const AlarmListView({super.key});

  @override
  State<AlarmListView> createState() => _AlarmListViewState();
}

class _AlarmListViewState extends State<AlarmListView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Ask for alarm permissions once when the list first appears.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AlarmScheduler.instance.requestPermissions();
    });
    // Refresh the "rings in …" countdowns every 30s.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _openEditor(BuildContext context, {AlarmItem? existing}) async {
    final store = AlarmScope.of(context);
    if (existing == null && store.atLimit) {
      _showLimitDialog(context);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AlarmEditPage(existing: existing)),
    );
  }

  void _showLimitDialog(BuildContext context) {
    final store = AlarmScope.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('已达免费上限'),
        content: Text('免费版最多 ${AlarmStore.freeLimit} 个闹钟。解锁 Pro 即可无限添加。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              store.unlockPro();
              Navigator.of(context).pop();
            },
            child: const Text('解锁 Pro'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = AlarmScope.of(context);
    final alarms = store.alarms;
    return Scaffold(
      body: alarms.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: alarms.length,
              itemBuilder: (context, i) => _AlarmCard(
                alarm: alarms[i],
                onEdit: () => _openEditor(context, existing: alarms[i]),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_alarm),
        label: const Text('新建闹钟'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alarm_off, size: 72, color: c.outline),
          const SizedBox(height: 16),
          Text('还没有闹钟', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('点击下方「新建闹钟」添加第一个',
              style: TextStyle(color: c.outline)),
        ],
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({required this.alarm, required this.onEdit});

  final AlarmItem alarm;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final store = AlarmScope.of(context);
    final c = Theme.of(context).colorScheme;
    final on = alarm.enabled;
    final now = DateTime.now();
    return Dismissible(
      key: ValueKey(alarm.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: c.errorContainer,
        child: Icon(Icons.delete_outline, color: c.onErrorContainer),
      ),
      onDismissed: (_) {
        store.delete(alarm);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 ${alarm.hhmm}')),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alarm.hhmm,
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w300,
                          height: 1.0,
                          color: on ? c.onSurface : c.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (alarm.label.isNotEmpty) alarm.label,
                          repeatLabel(alarm.weekdays),
                        ].join(' · '),
                        style: TextStyle(
                          color: on ? c.onSurfaceVariant : c.outline,
                        ),
                      ),
                      if (on) ...[
                        const SizedBox(height: 2),
                        Text(
                          formatUntil(untilNext(alarm, now)),
                          style: TextStyle(fontSize: 12, color: c.primary),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(
                  value: on,
                  onChanged: (v) => store.toggle(alarm, v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
