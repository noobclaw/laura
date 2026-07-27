import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'models.dart';
import 'recording_screen.dart';
import 'report_screen.dart';
import 'store.dart';
import 'ui_common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  final AutoSnoreStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StartCard(store: store),
            const SizedBox(height: 20),
            if (store.sessions.isNotEmpty) ...[
              Text(tr(zh: '记录', en: 'Nights'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...store.sessions.map((s) => _NightTile(session: s, store: store)),
              if (store.atFreeLimit)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tr(
                      zh: '免费版保留最近 ${AutoSnoreStore.freeSessionLimit} 晚,解锁 Pro 保存全部历史。',
                      en: 'Free keeps the last ${AutoSnoreStore.freeSessionLimit} nights — '
                          'unlock Pro for full history.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    tr(
                      zh: '把手机放在床头,点上方开始今晚的记录 🌙',
                      en: 'Put the phone by your bed and tap above to record tonight 🌙',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({required this.store});
  final AutoSnoreStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RecordingScreen(store: store),
        )),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: cs.primary,
                child: Icon(Icons.mic, size: 32, color: cs.onPrimary),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(zh: '开始记录', en: 'Start recording'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      tr(zh: '整夜离线记录鼾声', en: 'Record snoring all night, offline'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onPrimaryContainer.withValues(alpha: 0.8)),
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

class _NightTile extends StatelessWidget {
  const _NightTile({required this.session, required this.store});
  final SleepSession session;
  final AutoSnoreStore store;

  @override
  Widget build(BuildContext context) {
    final color = bandColor(session.band);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.18),
          child: Text('${session.score}',
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        title: Text(
            '${formatShortDate(session.startMs)} · ${bandLabel(session.band)}'),
        subtitle: Text(tr(
          zh: '${session.snoreCount} 次鼾声 · ${formatDuration(session.durationMs)}',
          en: '${session.snoreCount} snores · ${formatDuration(session.durationMs)}',
        )),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReportScreen(session: session, store: store),
        )),
        onLongPress: () => _confirmDelete(context),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '删除这一晚?', en: 'Delete this night?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              store.deleteSession(session.id);
              Navigator.of(ctx).pop();
            },
            child: Text(tr(zh: '删除', en: 'Delete')),
          ),
        ],
      ),
    );
  }
}
