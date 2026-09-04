import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'models.dart';
import 'recording_screen.dart';
import 'report_screen.dart';
import 'pro.dart';
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
        if (store.recoveredOnLaunch) {
          // A night that was being recorded when the app died has just been
          // promoted from its last checkpoint. Say so once.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            store.acknowledgeRecovery();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              duration: const Duration(seconds: 6),
              content: Text(tr(
                zh: '上次记录没有正常结束,已按最后一次保存的进度找回,标为「提前结束」。',
                en: 'The last night did not end normally; it was restored from its last checkpoint and marked "ended early".',
              )),
            ));
          });
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
              ...store.visibleSessions
                  .map((s) => _NightTile(session: s, store: store)),
              if (store.atFreeLimit)
                // The history gate itself: tappable, opens the Pro sheet
                // (a plain caption here was the one free-tier wall that
                // dead-ended without a way to unlock).
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(store.hiddenSessionCount > 0
                        ? tr(
                            zh: '还有 ${store.hiddenSessionCount} 晚在 Pro 里',
                            en: '${store.hiddenSessionCount} more night(s) in Pro',
                          )
                        : tr(zh: '保存全部历史', en: 'Keep every night')),
                    subtitle: Text(tr(
                      zh: '免费版显示最近 ${AutoSnoreStore.freeSessionLimit} 晚,解锁 Pro 查看全部历史。',
                      en: 'Free shows the last ${AutoSnoreStore.freeSessionLimit} nights — '
                          'unlock Pro for full history.',
                    )),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showProSheet(
                      context,
                      reason: tr(
                        zh: '免费版只显示最近 ${AutoSnoreStore.freeSessionLimit} 晚,更早的记录都还在,Pro 可以全部查看。',
                        en: 'The free tier shows the last ${AutoSnoreStore.freeSessionLimit} nights; older ones are kept and Pro shows them all.',
                      ),
                    ),
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

  /// First night only: the three things that decide whether the recording
  /// survives until morning, said before the user commits — not discovered
  /// at 06:00 from a report that stopped at 00:47.
  Future<void> _startNight(BuildContext context) async {
    if (!store.briefingSeen) {
      final go = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => _Briefing(),
      );
      if (go != true || !context.mounted) return;
      store.markBriefingSeen();
    }
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecordingScreen(store: store),
    ));
  }

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
            onTap: () => _startNight(context),
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

/// The pre-flight briefing shown once before the first night.
class _Briefing extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    Widget item(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(body,
                        style: text.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(zh: '睡前三件事', en: 'Three things before you sleep'),
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                zh: '做到了,早上的报告才是完整的一夜。',
                en: 'Do these and the morning report covers the whole night.',
              ),
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            item(
              Icons.power_outlined,
              tr(zh: '插上电', en: 'Plug it in'),
              tr(
                zh: '整夜采麦会耗电,别让手机半夜关机。',
                en: 'Listening all night uses battery; do not let the phone die at 3 am.',
              ),
            ),
            item(
              ios ? Icons.lock_outline : Icons.brightness_high_outlined,
              ios
                  ? tr(zh: '可以锁屏', en: 'You can lock the screen')
                  : tr(zh: '屏幕会保持常亮', en: 'The screen stays on'),
              ios
                  ? tr(
                      zh: '记录在后台继续。把手机屏幕朝下放在床头即可。',
                      en: 'Recording continues in the background. Just put the phone face down on the nightstand.',
                    )
                  : tr(
                      zh: '安卓没有后台录音,App 会锁住屏幕不熄。把亮度调到最低,屏幕朝下放。',
                      en: 'Android cannot record in the background, so the app keeps the screen awake. Turn brightness down and put it face down.',
                    ),
            ),
            item(
              Icons.do_not_disturb_on_outlined,
              ios
                  ? tr(zh: '开勿扰', en: 'Turn on Do Not Disturb')
                  : tr(zh: '别切走、开勿扰', en: 'Stay in the app, turn on Do Not Disturb'),
              ios
                  ? tr(
                      zh: '来电会打断录音,通话结束后自动继续。',
                      en: 'A call interrupts the recording; it resumes when the call ends.',
                    )
                  : tr(
                      zh: '切到别的 App 或接电话都会结束今晚的记录(已录部分会保留)。',
                      en: 'Switching apps or taking a call ends the night (what was recorded is kept).',
                    ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(zh: '知道了,开始记录', en: 'Got it, start recording')),
            ),
          ],
        ),
      ),
    );
  }
}
