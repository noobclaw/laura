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
            return EmptyState(
              icon: Icons.show_chart,
              title: tr(zh: '还需要更多夜晚', en: 'A little more data'),
              body: tr(
                zh: '记录至少两晚后,这里会显示鼾声评分的走势。',
                en: 'Record at least two nights to see your snore-score trend.',
              ),
            );
          }
          final double avg =
              nights.map((s) => s.score).reduce((a, b) => a + b) / nights.length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                tr(zh: '平均评分', en: 'Average score'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Text(
                avg.toStringAsFixed(0),
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: _TrendChart(nights: nights, avg: avg),
                ),
              ),
              const SizedBox(height: 16),
              ...nights.reversed.map((s) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: bandColor(s.band).withValues(alpha: 0.18),
                        child: Text('${s.score}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: bandColor(s.band))),
                      ),
                      title: Text(
                          '${formatShortDate(s.startMs)} · ${bandLabel(s.band)}'),
                      subtitle: Text(tr(
                        zh: '${s.snoreCount} 次 · ${s.snoreIndexPerHour.toStringAsFixed(1)} 次/时 · ${formatDuration(s.durationMs)}',
                        en: '${s.snoreCount} events · ${s.snoreIndexPerHour.toStringAsFixed(1)}/h · ${formatDuration(s.durationMs)}',
                      )),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.nights, required this.avg});
  final List<SleepSession> nights;
  final double avg;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final double avgFrac = (avg / 100).clamp(0.0, 1.0);
    return Column(
      children: [
        SizedBox(
          height: 150,
          child: LayoutBuilder(
            builder: (context, cons) {
              final double h = cons.maxHeight;
              final double avgY = h * (1 - avgFrac);
              return Stack(
                children: [
                  // Baseline.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(height: 1.5, color: cs.outlineVariant),
                  ),
                  // Bars.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: nights.map((s) {
                      final double frac = (s.score / 100).clamp(0.03, 1.0);
                      final Color c = bandColor(s.band);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 40),
                              child: Container(
                                height: h * frac,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      c,
                                      Color.lerp(c, Colors.white, 0.35)!,
                                    ],
                                  ),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  // Average reference line.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: avgY,
                    child: CustomPaint(
                      size: const Size(double.infinity, 1),
                      painter: _DashedLinePainter(cs.primary.withValues(alpha: 0.7)),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: (avgY - 15).clamp(0.0, h - 14),
                    child: Text('avg',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: cs.primary)),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        // Date labels aligned under bars.
        Row(
          children: nights
              .map((s) => Expanded(
                    child: Text(
                      formatShortDate(s.startMs),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const double dash = 5, gap = 4;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
