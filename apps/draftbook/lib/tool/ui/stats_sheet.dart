import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../models.dart';
import '../store.dart';
import 'widgets.dart';

/// Writing stats: today against the daily goal, the current streak, and the
/// last fortnight as bars. Opened from the outline's app bar.
Future<void> showStatsSheet(
  BuildContext context,
  DraftbookStore store,
  Project project,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
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
    final ctl =
        TextEditingController(text: widget.project.targetWords > 0 ? '${widget.project.targetWords}' : '');
    final out = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '全书目标字数', en: 'Whole-book target')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: tr(zh: '例如 80000,留空表示不设目标', en: 'e.g. 80000 — leave empty for none'),
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
            child: Text(tr(zh: '保存', en: 'Save')),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (out == null) return;
    final parsed = int.tryParse(out.trim());
    widget.store.updateProject(widget.project, targetWords: parsed ?? 0);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final store = widget.store;
    final today = store.todayWords;
    final goal = store.dailyGoal;
    final days = store.recentDays(14);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr(zh: '写作统计', en: 'Writing stats'), style: text.titleLarge),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RollingCount(value: today, style: text.displaySmall),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      goal > 0
                          ? tr(
                              zh: '字 / 今日目标 ${groupedCount(goal)}',
                              en: 'words today of ${groupedCount(goal)}',
                            )
                          : tr(zh: '字(今天)', en: 'words today'),
                      style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              if (goal > 0) ...[
                const SizedBox(height: 10),
                ProgressRail(value: today / goal),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatPill(
                    icon: Icons.local_fire_department_outlined,
                    label: tr(zh: '连续达标', en: 'day streak'),
                    value: '${store.streakDays}',
                    tone: store.streakDays > 0 ? cs.primary : null,
                  ),
                  StatPill(
                    icon: Icons.menu_book_outlined,
                    label: tr(zh: '全书', en: 'in the book'),
                    value: groupedCount(widget.project.words),
                  ),
                  if (widget.project.targetWords > 0)
                    StatPill(
                      icon: Icons.flag_outlined,
                      label: tr(zh: '还差', en: 'to go'),
                      value: groupedCount(
                        (widget.project.targetWords - widget.project.words)
                            .clamp(0, widget.project.targetWords),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text(tr(zh: '最近两周', en: 'The last two weeks'), style: text.titleSmall),
              const SizedBox(height: 10),
              SizedBox(
                height: 108,
                child: _DayBars(days: days, goal: goal),
              ),
              const SizedBox(height: 22),
              Text(tr(zh: '每日目标', en: 'Daily goal'), style: text.titleSmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final g in _goals)
                    ChoiceChip(
                      label: Text(groupedCount(g)),
                      selected: goal == g,
                      onSelected: (_) {
                        store.setDailyGoal(g);
                        setState(() {});
                      },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _editTarget,
                icon: const Icon(Icons.flag_outlined),
                label: Text(
                  widget.project.targetWords > 0
                      ? tr(
                          zh: '全书目标:${groupedCount(widget.project.targetWords)} 字',
                          en: 'Book target: ${groupedCount(widget.project.targetWords)} words',
                        )
                      : tr(zh: '设置全书目标', en: 'Set a book target'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr(
                  zh: '统计只按「本机今天写了多少字」记,删改会相应扣回;数据不离开手机。',
                  en: 'Counts are the words added on this device today; cuts are '
                      'subtracted again. None of it leaves the phone.',
                ),
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fourteen bars, one per day, with the goal as a dashed rule across them.
class _DayBars extends StatelessWidget {
  const _DayBars({required this.days, required this.goal});

  final List<int> days;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final peak = [
      goal.toDouble(),
      ...days.map((d) => d.toDouble()),
    ].reduce((a, b) => a > b ? a : b);
    final max = peak <= 0 ? 1.0 : peak;

    return Semantics(
      label: tr(
        zh: '最近 ${days.length} 天每天写的字数',
        en: 'Words written on each of the last ${days.length} days',
      ),
      excludeSemantics: true,
      child: Stack(
        children: [
          if (goal > 0)
            Positioned(
              left: 0,
              right: 0,
              // Bars are 84 tall and sit 18 above the bottom (6 gap + label).
              bottom: 18 + 84 * (goal / max),
              child: Container(height: 1, color: cs.outlineVariant),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: days[i] / max),
                          duration: reduce
                              ? Duration.zero
                              : Duration(milliseconds: 420 + i * 24),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => Container(
                            height: (84 * v).clamp(2.0, 84.0),
                            decoration: BoxDecoration(
                              color: goal > 0 && days[i] >= goal
                                  ? cs.primary
                                  : cs.primary.withValues(alpha: 0.32),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (i == 0 || i == days.length - 1)
                          Text(
                            i == 0
                                ? tr(zh: '${days.length} 天前', en: '${days.length}d')
                                : tr(zh: '今天', en: 'today'),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 9.5,
                                ),
                          )
                        else
                          const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
