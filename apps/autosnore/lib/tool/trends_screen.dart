import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'models.dart';
import 'store.dart';
import 'ui_common.dart';

/// Pro: snore score across recent nights, so trends over time are visible.
class TrendsScreen extends StatelessWidget {
  const TrendsScreen({super.key, required this.store});

  final AutoSnoreStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '趋势', en: 'Trends'))),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          // Oldest → newest so the chart reads left-to-right in time.
          final nights = store.sessions.reversed.toList();
          if (nights.length < 2) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr(
                    zh: '记录至少两晚后,这里会显示鼾声评分走势。',
                    en: 'Record at least two nights to see your snore-score trend.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            );
          }
          final double avg =
              nights.map((s) => s.score).reduce((a, b) => a + b) / nights.length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                tr(zh: '平均评分 ${avg.toStringAsFixed(0)}', en: 'Average score ${avg.toStringAsFixed(0)}'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _BarChart(nights: nights),
                ),
              ),
              const SizedBox(height: 16),
              ...nights.reversed.map((s) => ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: bandColor(s.band).withValues(alpha: 0.2),
                      child: Text('${s.score}',
                          style: TextStyle(
                              fontSize: 12, color: bandColor(s.band))),
                    ),
                    title: Text(
                        '${formatShortDate(s.startMs)} · ${bandLabel(s.band)}'),
                    subtitle: Text(tr(
                      zh: '${s.snoreCount} 次 · ${s.snoreIndexPerHour.toStringAsFixed(1)} 次/时 · ${formatDuration(s.durationMs)}',
                      en: '${s.snoreCount} events · ${s.snoreIndexPerHour.toStringAsFixed(1)}/h · ${formatDuration(s.durationMs)}',
                    )),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.nights});
  final List<SleepSession> nights;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: nights.map((s) {
          final double h = (s.score / 100).clamp(0.03, 1.0) * 130;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${s.score}',
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Container(
                    height: h,
                    decoration: BoxDecoration(
                      color: bandColor(s.band),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(formatShortDate(s.startMs),
                      style: Theme.of(context).textTheme.labelSmall,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
