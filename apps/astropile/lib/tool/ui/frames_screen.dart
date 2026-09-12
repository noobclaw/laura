import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../engine/stack.dart';
import '../models.dart';
import '../pro.dart';
import '../store.dart';
import 'run_screen.dart';
import 'widgets.dart';

/// The frames the user picked, what is wrong with any of them, and the two
/// decisions that matter before a run: which frame is the reference, and how
/// the rest are combined.
class FramesScreen extends StatefulWidget {
  const FramesScreen({
    super.key,
    required this.store,
    required this.frames,
    this.scratchDir,
  });
  final AstroStore store;
  final List<SourceFrame> frames;

  /// Directory of HEIC renditions written during import, owned by this
  /// screen: it is deleted when the screen goes away, rather than waiting
  /// for the next cold start to sweep it.
  final String? scratchDir;

  @override
  State<FramesScreen> createState() => _FramesScreenState();
}

class _FramesScreenState extends State<FramesScreen> {
  late final List<SourceFrame> _frames = List.of(widget.frames);
  final Set<String> _excluded = {};
  String? _referenceId;

  // Plain defaults, not `late`: `_recompute` calls `_precheck` while it is
  // still deciding the majority exposure, so these must be readable before
  // they are final. An empty majority simply means "no exposure opinion yet".
  int _refWidth = 0;
  int _refHeight = 0;
  String _majorityExposure = '';

  /// Frames the tier limit removed from the selection, so the user is told
  /// rather than left wondering why some boxes are unticked.
  int _trimmedByLimit = 0;
  final Set<String> _trimmedIds = {};
  bool _starting = false;
  late bool _wasPro = widget.store.pro;

  @override
  void initState() {
    super.initState();
    _recompute();
    widget.store.addListener(_onStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _announceTrim());
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    final scratch = widget.scratchDir;
    if (scratch != null) {
      Directory(scratch).delete(recursive: true).catchError((Object e) {
        debugPrint('import cleanup skipped: $e');
        return Directory(scratch);
      });
    }
    super.dispose();
  }

  /// Buying Pro from this screen must put the frames the free limit unticked
  /// straight back in — otherwise the purchase looks like it did nothing.
  void _onStoreChanged() {
    if (_wasPro || !widget.store.pro) return;
    _wasPro = true;
    if (_trimmedIds.isEmpty) return;
    setState(() {
      _excluded.removeAll(_trimmedIds);
      _recompute();
    });
  }

  void _announceTrim() {
    if (!mounted || _trimmedByLimit <= 0) return;
    if (widget.store.pro) {
      showNotice(
          context,
          tr(
            zh: '一次最多叠 $kProFrameLimit 张,已保留前 $kProFrameLimit 张。',
            en: 'Up to $kProFrameLimit frames per stack — the first $kProFrameLimit are kept.',
          ));
      return;
    }
    showProSheet(context,
        reason: tr(
          zh: '免费版一次最多叠 $kFreeFrameLimit 张,你选了 ${_frames.length} 张 —— 已为你保留前 $kFreeFrameLimit 张,其余先取消了勾选。',
          en: 'The free tier stacks $kFreeFrameLimit frames at a time and you picked ${_frames.length}. The first $kFreeFrameLimit are kept; the rest are unticked for now.',
        ));
  }

  /// The size most frames share wins: a burst with one stray screenshot must
  /// not decide that the burst is the odd one out.
  void _recompute() {
    final sizeCount = <String, int>{};
    for (final f in _frames) {
      final k = '${f.width}x${f.height}';
      sizeCount[k] = (sizeCount[k] ?? 0) + 1;
    }
    var bestKey = '';
    var bestN = -1;
    sizeCount.forEach((k, n) {
      if (n > bestN) {
        bestN = n;
        bestKey = k;
      }
    });
    final parts = bestKey.split('x');
    _refWidth = int.tryParse(parts.first) ?? 0;
    _refHeight = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    final expCount = <String, int>{};
    for (final f in _frames) {
      if (_precheck(f) == FramePrecheck.sizeMismatch) continue;
      expCount[f.exposureKey] = (expCount[f.exposureKey] ?? 0) + 1;
    }
    var expKey = '';
    var expN = -1;
    expCount.forEach((k, n) {
      if (n > expN) {
        expN = n;
        expKey = k;
      }
    });
    _majorityExposure = expKey;

    // Auto-exclude what cannot be stacked, and trim to the tier's limit.
    _excluded.removeWhere((id) => !_frames.any((f) => f.id == id));
    for (final f in _frames) {
      if (_precheck(f) == FramePrecheck.sizeMismatch) _excluded.add(f.id);
    }
    final limit = widget.store.frameLimit;
    var kept = 0;
    _trimmedByLimit = 0;
    _trimmedIds.clear();
    for (final f in _frames) {
      if (_excluded.contains(f.id)) continue;
      kept++;
      if (kept > limit) {
        _excluded.add(f.id);
        _trimmedIds.add(f.id);
        _trimmedByLimit++;
      }
    }
    if (_referenceId == null || _excluded.contains(_referenceId)) {
      _referenceId = _included.isEmpty ? null : _included.first.id;
    }
  }

  FramePrecheck _precheck(SourceFrame f) {
    if (f.width != _refWidth || f.height != _refHeight) {
      return FramePrecheck.sizeMismatch;
    }
    if (_majorityExposure.isNotEmpty && f.exposureKey != _majorityExposure) {
      return FramePrecheck.exposureOutlier;
    }
    return FramePrecheck.ok;
  }

  List<SourceFrame> get _included =>
      [for (final f in _frames) if (!_excluded.contains(f.id)) f];

  int get _referenceIndex {
    final list = _included;
    final i = list.indexWhere((f) => f.id == _referenceId);
    return i < 0 ? 0 : i;
  }

  /// Bytes of scratch space this run will need: one aligned copy of every
  /// included frame, plus the stacked result.
  int get _scratchBytes {
    final n = _included.length;
    if (n == 0 || _refWidth == 0) return 0;
    final d = widget.store.scale.divisor;
    final px = (_refWidth ~/ d) * (_refHeight ~/ d);
    return px * 3 * (n + 1);
  }

  void _toggle(SourceFrame f) {
    final pre = _precheck(f);
    if (pre == FramePrecheck.sizeMismatch) {
      showNotice(
          context,
          tr(
            zh: '这张的画幅是 ${f.width}×${f.height},与其余 $_refWidth×$_refHeight 不一致,无法一起叠加。',
            en: 'This frame is ${f.width}×${f.height} while the rest are $_refWidth×$_refHeight — it cannot be stacked with them.',
          ));
      return;
    }
    final adding = _excluded.contains(f.id);
    if (adding && _included.length >= widget.store.frameLimit) {
      if (widget.store.pro) {
        showNotice(
            context,
            tr(
              zh: '一次最多叠 $kProFrameLimit 张。',
              en: 'Up to $kProFrameLimit frames per stack.',
            ));
      } else {
        showProSheet(context,
            reason: tr(
              zh: '免费版一次最多叠 $kFreeFrameLimit 张,你选的还有更多。',
              en: 'The free tier stacks up to $kFreeFrameLimit frames at a time, and you picked more.',
            ));
      }
      return;
    }
    setState(() {
      if (adding) {
        _excluded.remove(f.id);
      } else {
        _excluded.add(f.id);
        if (_referenceId == f.id) {
          _referenceId = _included.isEmpty ? null : _included.first.id;
        }
      }
    });
  }

  Future<void> _start() async {
    // Without this guard a double tap pushes two runs, each with its own
    // isolate and its own ~1 GB of scratch files.
    if (_starting) return;
    final list = _included;
    if (list.length < kMinStackFramesUi) {
      showNotice(
          context,
          tr(
            zh: '至少要选 2 张照片才能叠加。',
            en: 'Pick at least two photos to stack.',
          ));
      return;
    }
    setState(() => _starting = true);
    try {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RunScreen(
          store: widget.store,
          frames: list,
          referenceIndex: _referenceIndex,
          settings: widget.store.settings,
        ),
      ));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final included = _included;
        return Scaffold(
          appBar: AppBar(title: Text(tr(zh: '这一叠照片', en: 'This stack'))),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _Summary(
                        selected: included.length,
                        total: _frames.length,
                        width: _refWidth,
                        height: _refHeight,
                        scratchBytes: _scratchBytes,
                      ),
                      const SizedBox(height: 14),
                      SectionCard(
                        title: tr(zh: '叠加方式', en: 'Combine'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final m in StackMode.values)
                                  ChoiceChip(
                                    label: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(stackModeLabel(m)),
                                        if (m == StackMode.median && !widget.store.pro) ...[
                                          const SizedBox(width: 4),
                                          Icon(Icons.lock_outline,
                                              size: 14, color: cs.onSurfaceVariant),
                                        ],
                                      ],
                                    ),
                                    selected: widget.store.settings.mode == m,
                                    showCheckmark: false,
                                    onSelected: (_) {
                                      if (m == StackMode.median && !widget.store.pro) {
                                        showProSheet(context,
                                            reason: tr(
                                              zh: '中值叠加是 Pro 功能:它会自动丢掉只出现在少数帧里的东西 —— 飞机、卫星拖线、热噪点。',
                                              en: 'Median stacking is a Pro feature: it drops anything that appears in only a few frames — aircraft, satellite trails, hot pixels.',
                                            ));
                                        return;
                                      }
                                      widget.store.setMode(m);
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.store.settings.mode == StackMode.mean
                                  ? tr(
                                      zh: '平均:同样张数下降噪最多,但飞机和卫星会留下淡淡的痕迹。',
                                      en: 'Mean: the most noise reduction for a given number of frames, but aircraft and satellites leave a faint trace.')
                                  : tr(
                                      zh: '中值:自动去掉只出现在少数帧里的东西,降噪略少一点。',
                                      en: 'Median: drops anything that only a few frames saw, at slightly less noise reduction.'),
                              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SectionCard(
                        title: tr(zh: '工作分辨率', en: 'Working resolution'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final s in WorkScale.values)
                                  ChoiceChip(
                                    label: Text(workScaleLabel(s)),
                                    selected: widget.store.scale == s,
                                    showCheckmark: false,
                                    onSelected: (_) => widget.store.setScale(s),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr(
                                zh: '半分辨率大约快 4 倍、临时占用也只有 1/4,适合先试一叠看看效果。',
                                en: 'Half resolution runs about 4× faster and uses a quarter of the scratch space — good for a first look.',
                              ),
                              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          tr(zh: '照片(点缩略图设为参考帧)', en: 'Frames (tap a thumbnail to make it the reference)'),
                          style: text.titleSmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                      for (final (i, f) in _frames.indexed)
                        _FrameRow(
                          key: ValueKey(f.id),
                          index: i,
                          frame: f,
                          precheck: _precheck(f),
                          included: !_excluded.contains(f.id),
                          isReference: f.id == _referenceId,
                          onToggle: () => _toggle(f),
                          onMakeReference: () {
                            if (_excluded.contains(f.id)) {
                              _toggle(f);
                              if (_excluded.contains(f.id)) return;
                            }
                            setState(() => _referenceId = f.id);
                          },
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: PressScale(
                    enabled: included.length >= kMinStackFramesUi && !_starting,
                    child: FilledButton(
                      onPressed:
                          included.length >= kMinStackFramesUi && !_starting ? _start : null,
                      // Idle → starting: the icon gives way to a spinner and
                      // the label to "starting", cross-faded rather than
                      // swapped, so the press reads as a state change.
                      child: AnimatedSwitcher(
                        duration: animMs(context, 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SizeTransition(
                              sizeFactor: anim, axis: Axis.horizontal, child: child),
                        ),
                        child: Row(
                          key: ValueKey(_starting),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_starting)
                              const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                            else
                              const Icon(Icons.auto_awesome),
                            const SizedBox(width: 10),
                            Text(_starting
                                ? tr(zh: '正在启动…', en: 'Starting…')
                                : tr(
                                    zh: '开始叠加 ${included.length} 张',
                                    en: 'Stack ${included.length} frames',
                                  )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Two frames is the smallest thing worth calling a stack.
const int kMinStackFramesUi = 2;

class _Summary extends StatelessWidget {
  const _Summary({
    required this.selected,
    required this.total,
    required this.width,
    required this.height,
    required this.scratchBytes,
  });
  final int selected;
  final int total;
  final int width;
  final int height;
  final int scratchBytes;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: kSkyGradient,
        ),
      ),
      // Both columns flex: at a large text scale the English captions are
      // wider than half the strip, and a rigid Row would paint past the edge.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    CountUpText(selected,
                        ms: 400, style: text.displaySmall?.copyWith(color: AstroColors.star)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6, left: 4),
                      child: Text('/$total',
                          style: text.titleMedium
                              ?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
                    ),
                  ],
                ),
                Text(tr(zh: '张参与叠加', en: 'frames in the stack'),
                    softWrap: true,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall
                        ?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$width×$height',
                    softWrap: true,
                    maxLines: 2,
                    textAlign: TextAlign.end,
                    style: text.titleSmall?.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  tr(
                    zh: '临时占用约 ${formatBytes(scratchBytes)}',
                    en: 'about ${formatBytes(scratchBytes)} of scratch space',
                  ),
                  softWrap: true,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style:
                      text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameRow extends StatelessWidget {
  const _FrameRow({
    super.key,
    required this.index,
    required this.frame,
    required this.precheck,
    required this.included,
    required this.isReference,
    required this.onToggle,
    required this.onMakeReference,
  });

  final int index;
  final SourceFrame frame;
  final FramePrecheck precheck;
  final bool included;
  final bool isReference;
  final VoidCallback onToggle;
  final VoidCallback onMakeReference;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final broken = precheck == FramePrecheck.sizeMismatch;
    // Ticking a frame in or out, or promoting it to reference, moves the
    // card's outline and dims the row — animated, so the eye follows the
    // change instead of hunting for it.
    final status = AstroColors.of(context);
    final border = isReference
        ? status.aligned
        : included
            ? cs.outlineVariant.withValues(alpha: 0.35)
            : Colors.transparent;
    return RiseIn(
      index: index,
      child: AnimatedContainer(
        duration: animMs(context, 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: included ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border, width: isReference ? 1.6 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: tr(zh: '设为参考帧', en: 'Use as the reference frame'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: broken ? null : onMakeReference,
                  child: AnimatedOpacity(
                    opacity: included ? 1 : 0.4,
                    duration: animMs(context, 220),
                    child: FrameThumb(path: frame.path),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(frame.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium),
                        ),
                        AnimatedSwitcher(
                          duration: animMs(context, 200),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(scale: anim, child: child),
                          ),
                          child: isReference
                              ? Padding(
                                  key: const ValueKey('ref'),
                                  padding: const EdgeInsets.only(left: 6),
                                  child: StatusPill(
                                    label: tr(zh: '参考帧', en: 'REFERENCE'),
                                    color: status.reference,
                                    icon: Icons.center_focus_strong,
                                  ),
                                )
                              : const SizedBox.shrink(key: ValueKey('none')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      frame.exposureSummary.isEmpty
                          ? '${frame.width}×${frame.height} · ${formatBytes(frame.bytes)}'
                          : '${frame.exposureSummary} · ${formatBytes(frame.bytes)}',
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (broken) ...[
                      const SizedBox(height: 5),
                      Text(
                        tr(
                          zh: '画幅 ${frame.width}×${frame.height} 与其余不一致,不能参与叠加',
                          en: '${frame.width}×${frame.height} does not match the rest — cannot be stacked',
                        ),
                        style: text.bodySmall?.copyWith(color: status.bad),
                      ),
                    ] else if (precheck == FramePrecheck.exposureOutlier) ...[
                      const SizedBox(height: 5),
                      Text(
                        tr(
                          zh: '曝光设置与多数帧不同,会拉偏平均值',
                          en: 'Shot with different exposure settings than most frames',
                        ),
                        style: text.bodySmall?.copyWith(color: status.warn),
                      ),
                    ],
                  ],
                ),
              ),
              Checkbox(
                value: included,
                activeColor: status.aligned,
                checkColor: Theme.of(context).brightness == Brightness.dark
                    ? AstroInk.deep
                    : Colors.white,
                onChanged: broken ? null : (_) => onToggle(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
