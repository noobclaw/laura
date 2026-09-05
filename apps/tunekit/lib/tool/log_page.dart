import 'package:flutter/material.dart';

import '../core/day_change.dart';
import '../core/l10n.dart';
import 'app_theme.dart';
import 'painters.dart';
import 'pro.dart';
import 'store.dart';
import 'ui_common.dart';

/// Practice log: minutes per tool, tuning accuracy, drills and streak.
class LogPage extends StatefulWidget {
  const LogPage({super.key, required this.store});
  final TuneKitStore store;

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  int _days = 7;
  final DayChangeNotifier _day = DayChangeNotifier()..start();

  @override
  void dispose() {
    _day.dispose();
    super.dispose();
  }

  void _pickRange(int d) {
    if (d > TuneKitStore.freeHistoryDays && !widget.store.pro) {
      showProSheet(context,
          reason: tr(
            zh: '免费版保留最近 7 天的记录;30 天趋势与更久的历史是 Pro 功能。',
            en: 'Free keeps the last 7 days; 30-day trends and older history are Pro.',
          ));
      return;
    }
    setState(() => _days = d);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.store, _day]),
      builder: (context, _) {
        final store = widget.store;
        final cs = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;
        final today = store.today();
        final days = store.visibleDays(_days);
        final logs = [for (final d in days) store.dayAt(d)];
        final hasAny = store.days.values.any((l) => l.totalSec > 0 || l.tuneSamples > 0 || l.drillAnswered > 0);

        final bars = [
          for (final l in logs)
            [
              (l?.tunerSec ?? 0) / 60,
              (l?.metroSec ?? 0) / 60,
              (l?.practiceSec ?? 0) / 60,
            ],
        ];
        final labels = [
          for (var i = 0; i < days.length; i++)
            _days <= 7 ? weekdayShort(days[i]) : (i % 5 == 0 || i == days.length - 1 ? '${days[i].day}' : ''),
        ];
        final accuracy = [for (final l in logs) l?.inTuneRatio];

        var samples = 0;
        var absSum = 0.0;
        var inTune = 0;
        var answered = 0;
        var correct = 0;
        var checks = 0;
        for (final l in logs) {
          if (l == null) continue;
          samples += l.tuneSamples;
          absSum += l.tuneAbsCentsSum;
          inTune += l.inTuneSamples;
          answered += l.drillAnswered;
          correct += l.drillCorrect;
          checks += l.checksPassed;
        }
        final periodSec = logs.fold(0, (a, l) => a + (l?.totalSec ?? 0));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Hero: today + streak.
            Container(
              decoration: BoxDecoration(
                gradient: heroGradient(Theme.of(context).brightness),
                borderRadius: BorderRadius.circular(28),
              ),
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(zh: '今天练了', en: 'Practised today'),
                            style: text.labelLarge?.copyWith(color: Colors.white70)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('${today.totalMinutes}',
                                style: text.displayLarge?.copyWith(color: Colors.white, fontSize: 64, height: 1.1)),
                            const SizedBox(width: 6),
                            Text(tr(zh: '分钟', en: 'min'),
                                style: text.titleMedium?.copyWith(color: Colors.white70)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          children: [
                            _Mini(color: cs.primary, label: tr(zh: '调音', en: 'Tune'), seconds: today.tunerSec),
                            _Mini(color: kBeatAmber, label: tr(zh: '节拍', en: 'Beat'), seconds: today.metroSec),
                            _Mini(color: kInTuneGreen, label: tr(zh: '练习', en: 'Practice'), seconds: today.practiceSec),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Icon(Icons.local_fire_department,
                          color: store.streak > 0 ? kBeatAmber : Colors.white38, size: 36),
                      Text('${store.streak}',
                          style: text.headlineMedium?.copyWith(color: Colors.white)),
                      Text(tr(zh: '天连续', en: 'day streak'),
                          style: text.labelSmall?.copyWith(color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ),
            if (!hasAny) ...[
              const SizedBox(height: 16),
              GuidanceCard(
                icon: Icons.music_note,
                title: tr(zh: '还没有记录', en: 'Nothing logged yet'),
                body: tr(
                  zh: '调音、开节拍器或做一次弹奏检查,时间和音准都会自动记在这里。每天练满 1 分钟就算连续。',
                  en: 'Tune, run the metronome or do a play-and-check; time and accuracy land here automatically. A minute a day keeps the streak.',
                ),
              ),
            ] else ...[
              SectionTitle(
                tr(zh: '每日练习时长', en: 'Daily practice'),
                trailing: SegmentedButton<int>(
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(value: 7, label: Text(tr(zh: '7 天', en: '7d'))),
                    ButtonSegment(
                      value: 30,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tr(zh: '30 天', en: '30d')),
                          if (!store.pro) ...[const SizedBox(width: 4), const Icon(Icons.lock_outline, size: 13)],
                        ],
                      ),
                    ),
                  ],
                  selected: {_days},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _pickRange(s.first),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 150,
                        child: CustomPaint(
                          painter: StackedBarPainter(
                            bars: bars,
                            colors: [cs.primary, kBeatAmber, kInTuneGreen],
                            labels: labels,
                            scheme: cs,
                            highlightIndex: bars.length - 1,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Legend(color: cs.primary, label: tr(zh: '调音', en: 'Tuner')),
                          const SizedBox(width: 14),
                          _Legend(color: kBeatAmber, label: tr(zh: '节拍器', en: 'Metronome')),
                          const SizedBox(width: 14),
                          _Legend(color: kInTuneGreen, label: tr(zh: '练习', en: 'Practice')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      value: '${periodSec ~/ 60}',
                      unit: tr(zh: '分钟', en: 'min'),
                      label: tr(zh: '近 $_days 天合计', en: 'Last $_days days'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      value: '${logs.where((l) => (l?.totalSec ?? 0) >= 60).length}',
                      unit: '/ $_days',
                      label: tr(zh: '练习天数', en: 'Days practised'),
                    ),
                  ),
                ],
              ),
              SectionTitle(tr(zh: '音准', en: 'Tuning accuracy')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 120,
                        child: CustomPaint(
                          painter: AccuracyLinePainter(values: accuracy, scheme: cs, labels: labels),
                          size: Size.infinite,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(zh: '每日稳定读数落在 ±5 音分内的比例', en: 'Share of steady readings within ±5 cents, per day'),
                        style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      value: samples == 0 ? '—' : '${(inTune * 100 / samples).round()}',
                      unit: samples == 0 ? null : '%',
                      label: tr(zh: '在 ±5¢ 内', en: 'Within ±5¢'),
                      color: kInTuneGreen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      value: samples == 0 ? '—' : (absSum / samples).toStringAsFixed(1),
                      unit: samples == 0 ? null : '¢',
                      label: tr(zh: '平均偏差', en: 'Mean deviation'),
                    ),
                  ),
                ],
              ),
              SectionTitle(tr(zh: '和弦与音阶', en: 'Chords & scales')),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      value: '$checks',
                      label: tr(zh: '弹奏检查通过', en: 'Checks passed'),
                      color: kInTuneGreen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      value: answered == 0 ? '—' : '${(correct * 100 / answered).round()}',
                      unit: answered == 0 ? null : '%',
                      label: tr(zh: '训练正确率 ($answered 题)', en: 'Drill accuracy ($answered)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      value: '${store.drillBest}',
                      label: tr(zh: '训练最佳', en: 'Drill best'),
                      color: kBeatAmber,
                    ),
                  ),
                ],
              ),
              if (!store.pro) ...[
                const SizedBox(height: 16),
                Text(
                  tr(zh: '免费版显示最近 7 天;更早的记录会保留,解锁 Pro 后可见。', en: 'Free shows the last 7 days; older entries are kept and appear once Pro is unlocked.'),
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.color, required this.label, required this.seconds});
  final Color color;
  final String label;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$label ${formatMinSec(seconds)}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white70)),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
