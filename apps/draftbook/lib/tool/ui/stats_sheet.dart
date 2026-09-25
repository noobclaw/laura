import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../haptics.dart';
import '../models.dart';
import '../store.dart';
import 'line_gauge.dart';
import 'widgets.dart';

/// Writing stats: today on the line gauge, the streak and the book in plain
/// sentences, the last fortnight as a row of rules, and the two targets.
Future<void> showStatsSheet(
  BuildContext context,
  DraftbookStore store,
  Project project,
) {
  return showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: DbMotion.sheetStyle(context),
    isScrollControlled: true,
    builder: (ctx) => _StatsSheet(store: store, project: project),
  );
}

class _StatsSheet extends StatefulWidget {
  const _StatsSheet({required this.store, required this.project});

  final DraftbookStore store;
  final Project project;

  @override
  State<_StatsSheet> createState() => _StatsSheetState();
}

class _StatsSheetState extends State<_StatsSheet> {
  static const List<int> _goals = [250, 500, 800, 1000, 1500, 2000];

  Future<void> _editTarget() async {
    final ctl = TextEditingController(
        text: widget.project.targetWords > 0 ? '${widget.project.targetWords}' : '');
    final out = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '全书目标字数', en: 'Whole-book target')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: tr(zh: '例如 80000，留空表示不设目标', en: 'e.g. 80000, or empty for none'),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: Text(tr(zh: '保存目标', en: 'Save target')),
          ),
        ],
      ),
    );
    disposeNextFrame([ctl]);
    if (out == null) return;
    final parsed = int.tryParse(out.trim());
    widget.store.updateProject(widget.project, targetWords: parsed ?? 0);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final store = widget.store;
    final p = widget.project;
    final today = store.todayWords;
    final goal = store.dailyGoal;
    final days = store.recentDays(14);
    final streak = store.streakDays;
    final left = (p.targetWords - p.words).clamp(0, p.targetWords);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(DbSpace.gutter, 0, DbSpace.gutter, DbSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeading(title: tr(zh: '写作统计', en: 'Writing stats')),
            const SizedBox(height: DbSpace.x2_5),
            LineGauge(
              words: today,
              goal: goal,
              caption: goal > 0
                  ? tr(zh: '字，今天的目标 ${groupedCount(goal)}', en: 'of ${groupedCount(goal)} words today')
                  : tr(zh: '字（今天）', en: 'words today'),
            ),
            const SizedBox(height: DbSpace.x2),
            Text(
              [
                if (streak > 0)
                  tr(
                    zh: '已连续 $streak 天写到目标。',
                    en: streak == 1 ? 'Goal met today.' : '$streak days in a row at your goal.',
                  ),
                p.targetWords > 0
                    ? tr(
                        zh: '全书 ${groupedCount(p.words)} 字，离目标还差 ${groupedCount(left)}。',
                        en: '${groupedCount(p.words)} words in the book, ${groupedCount(left)} to go.',
                      )
                    : tr(
                        zh: '全书 ${groupedCount(p.words)} 字。',
                        en: '${groupedCount(p.words)} words in the book.',
                      ),
              ].join(tr(zh: '', en: ' ')),
              style: DbType.body.copyWith(color: c.ink),
            ),
            const SizedBox(height: DbSpace.x3),
            Text(tr(zh: '最近两周', en: 'The last two weeks'), style: DbType.strong.copyWith(color: c.ink)),
            const SizedBox(height: DbSpace.x1_5),
            SizedBox(height: DbSpace.chart, child: _DayRules(days: days, goal: goal)),
            const SizedBox(height: DbSpace.x3),
            Text(tr(zh: '每日目标', en: 'Daily goal'), style: DbType.strong.copyWith(color: c.ink)),
            const SizedBox(height: DbSpace.x1),
            Wrap(
              spacing: DbSpace.x1,
              runSpacing: DbSpace.x1,
              children: [
                for (final g in _goals)
                  ChoiceChip(
                    label: Text(groupedCount(g)),
                    selected: goal == g,
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: (_) {
                      Haptics.select();
                      store.setDailyGoal(g);
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: DbSpace.x2_5),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _editTarget,
                child: Text(
                  p.targetWords > 0
                      ? tr(
                          zh: '全书目标 ${groupedCount(p.targetWords)} 字（修改）',
                          en: 'Change the book target (${groupedCount(p.targetWords)} words)',
                        )
                      : tr(zh: '设置全书目标', en: 'Set a book target'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: DbSpace.x2),
            Text(
              tr(
                zh: '统计只按「本机今天写了多少字」记，删改会相应扣回；数据不离开手机。',
                en: 'Counts are the words added on this device today; cuts are '
                    'subtracted again. None of it leaves the phone.',
              ),
              style: DbType.meta.copyWith(color: c.inkMuted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fourteen days as fourteen rules standing on a baseline, the goal a dashed
/// hairline across them. A day that met the goal is set in ink and capped
/// with a small bar; the rest are grey. Height is words.
class _DayRules extends StatelessWidget {
  const _DayRules({required this.days, required this.goal});

  final List<int> days;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final met = days.where((d) => goal > 0 && d >= goal).length;
    return Semantics(
      label: tr(
        zh: '最近 ${days.length} 天每天写的字数，其中 $met 天达到目标。今天 ${groupedCount(days.last)} 字。',
        en: 'Words written on each of the last ${days.length} days; the goal was met on $met. '
            'Today: ${groupedCount(days.last)}.',
      ),
      excludeSemantics: true,
      child: Column(
        children: [
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: DbMotion.of(context, DbMotion.medium),
              curve: DbMotion.enter,
              builder: (context, t, _) => CustomPaint(
                size: Size.infinite,
                painter: _DayRulesPainter(
                  days: days,
                  goal: goal,
                  t: t,
                  ink: c.ink,
                  quiet: c.ruleStrong,
                  rule: c.rule,
                  accent: c.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: DbSpace.x0_5),
          Row(
            children: [
              Text(tr(zh: '${days.length} 天前', en: '${days.length} days ago'),
                  style: DbType.numeral.copyWith(color: c.inkMuted)),
              const Spacer(),
              Text(tr(zh: '今天', en: 'today'), style: DbType.numeral.copyWith(color: c.inkMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayRulesPainter extends CustomPainter {
  _DayRulesPainter({
    required this.days,
    required this.goal,
    required this.t,
    required this.ink,
    required this.quiet,
    required this.rule,
    required this.accent,
  });

  final List<int> days;
  final int goal;
  final double t;
  final Color ink;
  final Color quiet;
  final Color rule;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final peak = [goal, ...days].reduce((a, b) => a > b ? a : b);
    final max = peak <= 0 ? 1 : peak;
    final base = size.height - 1;
    canvas.drawLine(Offset(0, base), Offset(size.width, base),
        Paint()..color = rule..strokeWidth = DbRadius.hairline);
    if (goal > 0) {
      final gy = base - (base - 4) * (goal / max);
      final dash = Paint()
        ..color = accent
        ..strokeWidth = DbRadius.hairline;
      for (var x = 0.0; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, gy), Offset((x + 4).clamp(0, size.width), gy), dash);
      }
    }
    final slot = size.width / days.length;
    for (var i = 0; i < days.length; i++) {
      final x = slot * i + slot / 2;
      final h = (base - 4) * (days[i] / max) * t;
      final hit = goal > 0 && days[i] >= goal;
      final paint = Paint()
        ..color = hit ? ink : quiet
        ..strokeWidth = hit ? 3 : 2;
      if (days[i] > 0) {
        canvas.drawLine(Offset(x, base), Offset(x, base - h), paint);
        if (hit) {
          canvas.drawLine(Offset(x - 4, base - h), Offset(x + 4, base - h),
              Paint()..color = ink..strokeWidth = 1.5);
        }
      } else {
        canvas.drawCircle(Offset(x, base - 2), 1.2, Paint()..color = quiet);
      }
    }
  }

  @override
  bool shouldRepaint(_DayRulesPainter old) =>
      old.t != t || old.goal != goal || old.ink != ink || old.days != days;
}
