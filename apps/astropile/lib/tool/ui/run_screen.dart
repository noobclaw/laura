import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/review_prompt.dart';
import '../app_theme.dart';
import '../engine/pipeline.dart';
import '../models.dart';
import '../store.dart';
import 'result_screen.dart';
import 'star_field.dart';
import 'widgets.dart';

/// Runs the stack and shows it happening.
///
/// Two things are on screen at once on purpose: the ring, which answers "how
/// long", and the growing list of per-frame verdicts, which answers "is this
/// going to be any good". The second one is the product.
class RunScreen extends StatefulWidget {
  const RunScreen({
    super.key,
    required this.store,
    required this.frames,
    required this.referenceIndex,
    required this.settings,
  });

  final AstroStore store;
  final List<SourceFrame> frames;
  final int referenceIndex;
  final StackSettings settings;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  final StackRunner _runner = StackRunner();
  bool _handedOff = false;

  /// The verdict list is an [AnimatedList]: rows slide in as the isolate
  /// hands them back, rather than the whole list re-rendering. [_shown] is
  /// how many rows the list has been told about.
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _runner.addListener(_syncList);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _syncList() {
    final n = _runner.reports.length;
    final list = _listKey.currentState;
    if (list == null) {
      _shown = n;
      return;
    }
    while (_shown < n) {
      list.insertItem(_shown, duration: animMs(context, 320));
      _shown++;
    }
  }

  @override
  void dispose() {
    _runner.removeListener(_syncList);
    _runner.cancel();
    // The result screen takes ownership of the scratch files; if we never
    // got there, they are ours to delete.
    if (!_handedOff) _runner.disposeRun();
    _runner.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final outcome = await _runner.run(
      frames: widget.frames,
      referenceIndex: widget.referenceIndex,
      settings: widget.settings,
    );
    if (!mounted || outcome == null) return;
    widget.store.addStacked();
    // G8b-7: a finished stack is this app's core action (PLAN.md 评价弹窗).
    unawaited(ReviewPrompt.noteCoreAction());
    // From here the result screen owns the scratch directory and deletes it.
    _handedOff = true;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ResultScreen(store: widget.store, outcome: outcome),
    ));
  }

  String get _phaseLabel {
    if (_runner.isStopping) {
      // The frame already in flight has to finish; say so instead of letting
      // the button look unresponsive for the seconds that takes.
      return tr(
        zh: '正在停止 —— 当前这一张处理完就停',
        en: 'Stopping — it finishes the frame it is on first',
      );
    }
    switch (_runner.phase) {
      case RunPhase.preparing:
        return tr(zh: '正在读取参考帧', en: 'Reading the reference frame');
      case RunPhase.aligning:
        return tr(
          zh: '正在对齐 ${_runner.current}/${_runner.total} 张',
          en: 'Aligning ${_runner.current} of ${_runner.total}',
        );
      case RunPhase.stacking:
        return tr(
          zh: '正在合成 ${_runner.current}/${_runner.total} 条',
          en: 'Combining band ${_runner.current} of ${_runner.total}',
        );
      case RunPhase.finishing:
        return tr(zh: '正在收尾', en: 'Finishing up');
      case RunPhase.cancelled:
        return tr(zh: '已停止', en: 'Stopped');
      case RunPhase.failed:
        return tr(zh: '叠加没有完成', en: 'The stack did not finish');
      case RunPhase.done:
      case RunPhase.idle:
        return tr(zh: '完成', en: 'Done');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _runner,
      builder: (context, _) {
        final running = _runner.isRunning;
        return PopScope(
          canPop: !running,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && running) _runner.cancel();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(tr(zh: '叠加中', en: 'Stacking')),
              automaticallyImplyLeading: !running,
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: _ProgressHero(
                      fraction: _runner.overallFraction,
                      label: _phaseLabel,
                      running: running,
                      stopping: _runner.isStopping,
                      phase: _runner.phase,
                    ),
                  ),
                  if (_runner.phase == RunPhase.failed && _runner.failure != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Card(
                        color: AstroColors.of(context).bad.withValues(alpha: 0.14),
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline, color: AstroColors.of(context).bad),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  runFailureText(_runner.failure!, _runner.failureDetail),
                                  style: text.bodyMedium?.copyWith(height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        AnimatedList(
                          key: _listKey,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                          initialItemCount: _shown,
                          itemBuilder: (context, i, anim) {
                            if (i >= _runner.reports.length) return const SizedBox.shrink();
                            final curved =
                                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
                            return SizeTransition(
                              sizeFactor: curved,
                              alignment: Alignment.topCenter,
                              child: FadeTransition(
                                opacity: curved,
                                child: _ReportRow(report: _runner.reports[i]),
                              ),
                            );
                          },
                        ),
                        IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _runner.reports.isEmpty ? 1 : 0,
                            duration: animMs(context, 250),
                            child: Center(
                              child: Text(
                                tr(zh: '逐帧结果会在这里出现', en: 'Per-frame results appear here'),
                                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    // Stop → Back crossfades when the run settles, instead of
                    // one button being swapped for another under the thumb.
                    child: AnimatedSwitcher(
                      duration: animMs(context, 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: running
                          ? OutlinedButton.icon(
                              key: const ValueKey('stop'),
                              onPressed: _runner.isStopping ? null : _runner.cancel,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: Text(_runner.isStopping
                                  ? tr(zh: '正在停止…', en: 'Stopping…')
                                  : tr(zh: '停止', en: 'Stop')),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52)),
                            )
                          : PressScale(
                              key: const ValueKey('back'),
                              child: FilledButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text(tr(zh: '返回', en: 'Back')),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressHero extends StatelessWidget {
  const _ProgressHero({
    required this.fraction,
    required this.label,
    required this.running,
    required this.stopping,
    required this.phase,
  });
  final double fraction;
  final String label;
  final bool running;
  final bool stopping;
  final RunPhase phase;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final settled = !running;
    final ringColor = phase == RunPhase.failed
        ? AstroColors.bad
        : phase == RunPhase.cancelled || stopping
            ? AstroColors.warn
            : AstroColors.aligned;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: kSkyGradient,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      // The ring is a TweenAnimationBuilder over the runner's fraction, so a
      // frame finishing moves the arc rather than teleporting it — and the
      // same eased value drives the star trails behind it, which pull in to
      // a single point as the stack lines up.
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: fraction),
        duration: animMs(context, 420),
        curve: Curves.easeOutCubic,
        builder: (context, f, _) => Stack(
          children: [
            Positioned.fill(child: StarField(seed: 11, density: 0.9, converge: f)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Column(
                children: [
                  SizedBox(
                    width: 128,
                    height: 128,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: running && f <= 0.001 ? null : f,
                            strokeWidth: 8,
                            strokeCap: StrokeCap.round,
                            backgroundColor: Colors.white.withValues(alpha: 0.10),
                            valueColor: AlwaysStoppedAnimation(ringColor),
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: animMs(context, 300),
                          switchInCurve: Curves.easeOutBack,
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: settled && phase != RunPhase.done
                              ? Icon(
                                  key: ValueKey(phase),
                                  phase == RunPhase.failed
                                      ? Icons.error_outline
                                      : Icons.stop_circle_outlined,
                                  size: 44,
                                  color: ringColor,
                                )
                              : Column(
                                  key: const ValueKey('pct'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${(f * 100).round()}',
                                        style: text.displaySmall
                                            ?.copyWith(color: AstroColors.star)),
                                    Text('%',
                                        style: text.labelSmall?.copyWith(
                                            color: AstroColors.silver.withValues(alpha: 0.7))),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: AnimatedSwitcher(
                      duration: animMs(context, 220),
                      child: Text(
                        label,
                        key: ValueKey(label),
                        textAlign: TextAlign.center,
                        style: text.titleMedium?.copyWith(color: AstroColors.silver),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: animMs(context, 220),
                    curve: Curves.easeOutCubic,
                    child: running
                        ? Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              tr(
                                zh: '请让本页保持在前台',
                                en: 'Keep this screen in the foreground',
                              ),
                              style: text.bodySmall
                                  ?.copyWith(color: AstroColors.silver.withValues(alpha: 0.6)),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
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

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report});
  final FrameReport report;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final failed = !report.ok;
    final status = AstroColors.of(context);
    final color = report.isReference
        ? status.reference
        : failed
            ? status.bad
            : scoreColor(context, report.score);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              report.isReference
                  ? Icons.center_focus_strong
                  : failed
                      ? Icons.cancel_outlined
                      : Icons.check_circle_outline,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(report.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  report.isReference
                      ? tr(
                          zh: '参考帧 · 检出 ${report.starsDetected} 颗星',
                          en: 'Reference · ${report.starsDetected} stars found')
                      : failed
                          ? alignFailureText(report.failure!)
                          : tr(
                              zh: '匹配 ${report.matchedStars}/${report.starsDetected} 颗 · 残差 ${report.rmsPixels.toStringAsFixed(2)} px',
                              en: '${report.matchedStars}/${report.starsDetected} stars matched · ${report.rmsPixels.toStringAsFixed(2)} px residual',
                            ),
                  style: text.bodySmall?.copyWith(
                      color: failed ? status.bad : cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (!report.isReference && !failed)
            CountUpText(report.score, style: text.titleMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}
