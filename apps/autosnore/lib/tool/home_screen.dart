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
            ] else ...[
              const SizedBox(height: 24),
              EmptyState(
                icon: Icons.bedtime_outlined,
                title: tr(zh: '今晚开始第一次记录', en: 'Record your first night'),
                body: tr(
                  zh: '把手机放在床头、接通电源,点上方开始。早晨你会看到一份鼾声报告 🌙',
                  en: 'Put the phone by your bed, keep it charging, and tap above. '
                      'A snore report will be waiting in the morning 🌙',
                ),
              ),
            ],
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2C2F73), Color(0xFF5661E0)],
            ),
          ),
          child: InkWell(
            splashColor: Colors.white24,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RecordingScreen(store: store),
            )),
            child: SizedBox(
              height: 208,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned(
                    right: -24,
                    top: -24,
                    child: Icon(Icons.nightlight_round,
                        size: 170, color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.30),
                                blurRadius: 26,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.mic,
                              size: 34, color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          tr(zh: '开始记录', en: 'Start recording'),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr(
                            zh: '整夜离线记录鼾声 · 零联网',
                            en: 'Record all night · fully offline',
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.82)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
