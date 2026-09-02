import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'export.dart';
import 'gauge_painter.dart';
import 'models.dart';
import 'store.dart';
import 'timeline_painter.dart';
import 'trends_screen.dart';
import 'ui_common.dart';

/// Morning report for a single night.
class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key, required this.session, required this.store});

  final SleepSession session;
  final AutoSnoreStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(zh: '晨间报告', en: 'Morning report')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _WindowLine(session: session),
          if (session.endedEarly) ...[
            const SizedBox(height: 12),
            _EndedEarlyBanner(),
          ],
          if (session.interruptedMs >= 60000) ...[
            const SizedBox(height: 12),
            _InterruptedBanner(ms: session.interruptedMs),
          ],
          const SizedBox(height: 16),
          _ScoreCard(session: session),
          const SizedBox(height: 16),
          _StatsGrid(session: session),
          const SizedBox(height: 20),
          Text(tr(zh: '整夜响度', en: 'Loudness through the night'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Column(
                children: [
                  SizedBox(
                    height: 90,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: NightTimelinePainter(
                        session: session,
                        barColor: cs.primary,
                        trackColor: cs.outlineVariant,
                        labelColor: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatClock(session.startMs),
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(formatClock(session.endMs),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _RhythmNote(session: session),
          const SizedBox(height: 20),
          _ProActions(session: session, store: store),
          const SizedBox(height: 20),
          Text(tr(zh: '事件明细', en: 'Events'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (session.events.isEmpty)
            EmptyState(
              icon: Icons.nights_stay_outlined,
              title: tr(zh: '安静的一夜', en: 'A quiet night'),
              body: tr(
                zh: '没有记录到明显的鼾声或响声 🌙',
                en: 'No notable snoring or noise was recorded 🌙',
              ),
            )
          else
            ...List.generate(session.events.length, (i) {
              final e = session.events[i];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  child: Text('${i + 1}',
                      style: const TextStyle(fontSize: 11)),
                ),
                title: Text(formatClock(e.startMs)),
                subtitle: Text(tr(
                  zh: '时长 ${formatDuration(e.durationMs)} · 峰值 ${e.peakDb.toStringAsFixed(0)} dB',
                  en: '${formatDuration(e.durationMs)} · peak ${e.peakDb.toStringAsFixed(0)} dB',
                )),
              );
            }),
        ],
      ),
    );
  }
}

class _EndedEarlyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              Theme.of(context).platform == TargetPlatform.iOS
                  ? tr(
                      zh: '记录没有正常结束(应用被关闭或手机重启)。这份报告只覆盖到最后一次保存的时刻。',
                      en: 'Recording did not end normally (the app was closed or the phone restarted). This report covers up to the last checkpoint.',
                    )
                  : tr(
                      zh: '记录提前结束了(应用离开了前台)。这份报告只覆盖到结束时刻。'
                          '整夜记录请保持应用在前台、屏幕常亮。',
                      en: 'Recording ended early (the app left the foreground). This '
                          'report only covers up to that point. For all-night '
                          'recording keep the app in the foreground with the screen on.',
                    ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowLine extends StatelessWidget {
  const _WindowLine({required this.session});
  final SleepSession session;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.bedtime_outlined, size: 20),
        const SizedBox(width: 8),
        Text(
          '${formatShortDate(session.startMs)} · '
          '${formatClock(session.startMs)}–${formatClock(session.endMs)} · '
          '${formatDuration(session.durationMs)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.session});
  final SleepSession session;

  @override
  Widget build(BuildContext context) {
    final color = bandColor(session.band);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size.square(92),
                    painter: ScoreGaugePainter(
                      value: session.score.toDouble(),
                      color: color,
                      trackColor: color.withValues(alpha: 0.16),
                    ),
                  ),
                  Text('${session.score}',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: color)),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(zh: '鼾声评分', en: 'Snore score'),
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(bandLabel(session.band),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: color, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      zh: '越低越安静(0–100)',
                      en: 'Lower is quieter (0–100)',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.session});
  final SleepSession session;

  @override
  Widget build(BuildContext context) {
    final loudest = session.loudest;
    final tiles = <Widget>[
      _Stat(
        label: tr(zh: '鼾声次数', en: 'Snore events'),
        value: '${session.snoreCount}',
      ),
      _Stat(
        label: tr(zh: '鼾声指数', en: 'Snore index'),
        value: session.snoreIndexPerHour.toStringAsFixed(1),
        hint: tr(zh: '次/小时', en: 'per hour'),
      ),
      _Stat(
        label: tr(zh: '鼾声占比', en: 'Time snoring'),
        value: '${session.snorePercent.toStringAsFixed(1)}%',
      ),
      _Stat(
        label: tr(zh: '最响', en: 'Loudest'),
        value: loudest == null ? '—' : '${loudest.peakDb.toStringAsFixed(0)} dB',
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: tiles,
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.hint});
  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (hint != null) ...[
                  const SizedBox(width: 4),
                  Text(hint!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RhythmNote extends StatelessWidget {
  const _RhythmNote({required this.session});
  final SleepSession session;

  @override
  Widget build(BuildContext context) {
    if (session.snoreCount < 2) return const SizedBox.shrink();
    final int r = session.rhythmicCount;
    final double share = session.snoreCount == 0 ? 0 : r / session.snoreCount;
    final bool rhythmic = share >= 0.5;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(rhythmic ? Icons.graphic_eq : Icons.blur_on, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rhythmic
                  ? tr(
                      zh: '响声呈规律节律,更可能是持续打鼾($r/${session.snoreCount} 次成节律)。',
                      en: 'Noises were rhythmic — likely sustained snoring '
                          '($r of ${session.snoreCount} in rhythm).')
                  : tr(
                      zh: '响声较零散,更像偶发环境噪音($r/${session.snoreCount} 次成节律)。',
                      en: 'Noises were scattered — more like occasional ambient '
                          'sounds ($r of ${session.snoreCount} in rhythm).'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProActions extends StatelessWidget {
  const _ProActions({required this.session, required this.store});
  final SleepSession session;
  final AutoSnoreStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.pro) {
          return Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.show_chart),
                  label: Text(tr(zh: '趋势', en: 'Trends')),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TrendsScreen(store: store),
                  )),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.ios_share),
                  label: Text(tr(zh: '导出 CSV', en: 'Export CSV')),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await shareSessionCsv(session);
                    if (!ok) {
                      messenger.showSnackBar(SnackBar(
                        content: Text(tr(
                            zh: '导出失败,请重试', en: 'Export failed, please retry')),
                      ));
                    }
                  },
                ),
              ),
            ],
          );
        }
        return Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text(tr(zh: '解锁 Pro', en: 'Unlock Pro')),
            subtitle: Text(tr(
              zh: '无限历史 · 跨夜趋势 · 两晚对比 · CSV 导出',
              en: 'Unlimited history · trends · night comparison · CSV export',
            )),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => PurchaseService.instance.buyPro(),
          ),
        );
      },
    );
  }
}

/// The microphone delivered nothing for this long. Without it, a night the
/// system muted at 01:10 would read as a perfectly quiet night.
class _InterruptedBanner extends StatelessWidget {
  const _InterruptedBanner({required this.ms});
  final int ms;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minutes = (ms / 60000).round();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.mic_off_outlined, size: 20, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                zh: '有 $minutes 分钟麦克风没有收到声音(被通知、来电或系统打断)。'
                    '这段时间的鼾声没有计入。',
                en: 'The microphone received nothing for $minutes min (a '
                    'notification, call or the system interrupted it). Snoring '
                    'in that window is not counted.',
              ),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
