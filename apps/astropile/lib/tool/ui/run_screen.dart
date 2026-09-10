import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../engine/pipeline.dart';
import '../models.dart';
import '../store.dart';
import 'result_screen.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
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
                        color: AstroColors.bad.withValues(alpha: 0.14),
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline, color: AstroColors.bad),
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
                    child: _runner.reports.isEmpty
                        ? Center(
                            child: Text(
                              tr(zh: '逐帧结果会在这里出现', en: 'Per-frame results appear here'),
                              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                            itemCount: _runner.reports.length,
                            itemBuilder: (context, i) =>
                                _ReportRow(report: _runner.reports[i]),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: running
                        ? OutlinedButton.icon(
                            onPressed: _runner.isStopping ? null : _runner.cancel,
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: Text(_runner.isStopping
                                ? tr(zh: '正在停止…', en: 'Stopping…')
                                : tr(zh: '停止', en: 'Stop')),
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52)),
                          )
                        : FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(tr(zh: '返回', en: 'Back')),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: kSkyGradient,
        ),
      ),
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
                    value: running && fraction > 0 ? fraction : (running ? null : fraction),
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(
                      phase == RunPhase.failed
                          ? AstroColors.bad
                          : phase == RunPhase.cancelled || stopping
                              ? AstroColors.warn
                              : AstroColors.reference,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${(fraction * 100).round()}',
                        style: text.displaySmall?.copyWith(color: Colors.white)),
                    Text('%',
                        style: text.labelSmall
                            ?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: Colors.white),
            ),
          ),
          if (running) ...[
            const SizedBox(height: 6),
            Text(
              tr(
                zh: '请让本页保持在前台',
                en: 'Keep this screen in the foreground',
              ),
              style:
                  text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ],
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
    final color = report.isReference
        ? AstroColors.reference
        : failed
            ? AstroColors.bad
            : scoreColor(report.score);
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
                      color: failed ? AstroColors.bad : cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (!report.isReference && !failed)
            Text('${report.score}',
                style: text.titleMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}
