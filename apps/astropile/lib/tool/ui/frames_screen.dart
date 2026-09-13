import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../engine/output.dart';
import '../engine/picker.dart';
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

  /// Optional calibration sets (Pro). Kept here rather than in the store: a
  /// dark frame is only meaningful for the burst it was shot alongside, so
  /// remembering it across sessions would be a trap.
  final List<SourceFrame> _darks = [];
  final List<SourceFrame> _flats = [];
  final List<String> _calibrationScratch = [];
  final FrameImporter _calibrationImporter = FrameImporter();
  bool _pickingCalibration = false;

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
    for (final scratch in [widget.scratchDir, ..._calibrationScratch]) {
      if (scratch == null) continue;
      Directory(scratch).delete(recursive: true).catchError((Object e) {
        debugPrint('import cleanup skipped: $e');
        return Directory(scratch);
      });
    }
    super.dispose();
  }

  /// One reason line per gated mode — a paywall that says "this is Pro" and
  /// nothing else does not help anyone decide.
  String _modeGateReason(StackMode m) => switch (m) {
        StackMode.median => tr(
            zh: '中值叠加是 Pro 功能:它会自动丢掉只出现在少数帧里的东西 —— 飞机、卫星拖线、热噪点。',
            en: 'Median stacking is a Pro feature: it drops anything that appears in only a few frames — aircraft, satellite trails, hot pixels.'),
        StackMode.kappaSigma => tr(
            zh: 'κ-σ 剪切是 Pro 功能:它按每个像素自己的统计量剔除异常值,既去掉飞机卫星,又比中值多留住降噪效果。',
            en: 'Kappa-sigma is a Pro feature: it rejects outliers by each pixel\'s own statistics, removing aircraft and satellites while keeping more of the noise reduction than median does.'),
        StackMode.mean || StackMode.max => '',
      };

  /// Pick a dark or flat set. Both go through the same system picker as the
  /// lights, so neither needs a storage permission.
  Future<void> _pickCalibration(CalibrationSlot slot) async {
    if (_pickingCalibration) return;
    if (!widget.store.canCalibrate) {
      showProSheet(context,
          reason: tr(
            zh: '暗场/平场校准是 Pro 功能:暗场扣掉传感器的热噪与坏点,平场抹平暗角和镜头上的灰尘印。',
            en: 'Dark and flat calibration is a Pro feature: darks subtract the sensor\'s thermal noise and hot pixels, flats even out vignetting and dust shadows.',
          ));
      return;
    }
    setState(() => _pickingCalibration = true);
    try {
      final result = await _calibrationImporter.pickFromLibrary();
      if (!mounted) return;
      if (result.scratchDir != null) _calibrationScratch.add(result.scratchDir!);
      if (result.error != null) {
        showNotice(context, result.error!,
            action: result.permissionDenied
                ? SnackBarAction(
                    label: tr(zh: '去设置', en: 'Settings'),
                    onPressed: openSystemSettings)
                : null);
        return;
      }
      if (result.frames.isEmpty) return; // cancelled
      // Wrong-size calibration frames are rejected here, with the numbers in
      // the message — finding out after a five-minute run would be worse.
      final good = [
        for (final f in result.frames)
          if (f.width == _refWidth && f.height == _refHeight) f
      ];
      final wrong = result.frames.length - good.length;
      if (good.isEmpty) {
        showNotice(
            context,
            tr(
              zh: '这些校准帧是 ${result.frames.first.width}×${result.frames.first.height},和这组照片的 $_refWidth×$_refHeight 不一致,用不了。',
              en: 'Those calibration frames are ${result.frames.first.width}×${result.frames.first.height} while this stack is $_refWidth×$_refHeight, so they cannot be used.',
            ));
        return;
      }
      setState(() {
        final target = slot == CalibrationSlot.dark ? _darks : _flats;
        target
          ..clear()
          ..addAll(good.take(kMaxCalibrationFrames));
      });
      final dropped = good.length - (good.length.clamp(0, kMaxCalibrationFrames));
      if (wrong > 0 || dropped > 0) {
        showNotice(
            context,
            tr(
              zh: '已采用 ${(good.length).clamp(0, kMaxCalibrationFrames)} 张,跳过 ${wrong + dropped} 张(画幅不符或超过 $kMaxCalibrationFrames 张上限)。',
              en: 'Using ${(good.length).clamp(0, kMaxCalibrationFrames)}; skipped ${wrong + dropped} (wrong pixel size, or over the $kMaxCalibrationFrames-frame cap).',
            ));
      }
    } finally {
      if (mounted) setState(() => _pickingCalibration = false);
    }
  }

  void _clearCalibration(CalibrationSlot slot) {
    setState(() => (slot == CalibrationSlot.dark ? _darks : _flats).clear());
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
    // Calibration frames are decoded to raw too, though only until their
    // master is built; while they are on disk this is the real high-water
    // mark, and understating it is how a run dies at frame 20.
    final calibration =
        widget.store.canCalibrate ? _darks.length + _flats.length + 2 : 0;
    return px * 3 * (n + 1 + calibration);
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
      final calibrate = widget.store.canCalibrate;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RunScreen(
          store: widget.store,
          frames: list,
          referenceIndex: _referenceIndex,
          settings: widget.store.settings,
          darkFrames: calibrate ? List.of(_darks) : const [],
          flatFrames: calibrate ? List.of(_flats) : const [],
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
                                        if (m.needsPro && !widget.store.pro) ...[
                                          const SizedBox(width: 4),
                                          Icon(Icons.lock_outline,
                                              size: 14, color: cs.onSurfaceVariant),
                                        ],
                                      ],
                                    ),
                                    selected: widget.store.settings.mode == m,
                                    showCheckmark: false,
                                    onSelected: (_) {
                                      if (m.needsPro && !widget.store.pro) {
                                        showProSheet(context, reason: _modeGateReason(m));
                                        return;
                                      }
                                      widget.store.setMode(m);
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              stackModeBlurb(widget.store.settings.mode),
                              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _CalibrationCard(
                        store: widget.store,
                        darks: _darks,
                        flats: _flats,
                        onPick: _pickCalibration,
                        onClear: _clearCalibration,
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

/// Calibration frames accepted per set. Past about a dozen the master stops
/// improving measurably, and every extra one is another full-frame decode
/// plus its scratch copy before the stack has even started.
const int kMaxCalibrationFrames = 12;

enum CalibrationSlot { dark, flat }

/// The optional dark/flat pair. Collapsed to two rows when empty, because
/// most stacks will never use it — but visible, because a user who owns
/// darks would never think to look for it in a menu.
class _CalibrationCard extends StatelessWidget {
  const _CalibrationCard({
    required this.store,
    required this.darks,
    required this.flats,
    required this.onPick,
    required this.onClear,
  });

  final AstroStore store;
  final List<SourceFrame> darks;
  final List<SourceFrame> flats;
  final void Function(CalibrationSlot) onPick;
  final void Function(CalibrationSlot) onClear;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return SectionCard(
      title: tr(zh: '校准帧(可选)', en: 'Calibration (optional)'),
      trailing: store.pro
          ? null
          : StatusPill(
              label: 'PRO',
              color: cs.primary,
              icon: Icons.workspace_premium,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CalibrationRow(
            icon: Icons.dark_mode_outlined,
            title: tr(zh: '暗场', en: 'Dark frames'),
            hint: tr(
              zh: '盖上镜头盖、用同样的 ISO 和快门拍几张 —— 扣掉传感器的热噪和坏点。',
              en: 'A few shots with the lens cap on at the same ISO and shutter — subtracts thermal noise and hot pixels.',
            ),
            frames: darks,
            onPick: () => onPick(CalibrationSlot.dark),
            onClear: () => onClear(CalibrationSlot.dark),
          ),
          const SizedBox(height: 12),
          _CalibrationRow(
            icon: Icons.wb_sunny_outlined,
            title: tr(zh: '平场', en: 'Flat frames'),
            hint: tr(
              zh: '对着均匀的亮面(晨昏天空、白墙)不改焦距拍几张 —— 抹平暗角和镜头上的灰尘印。',
              en: 'A few shots of an evenly lit surface (twilight sky, a white wall) without refocusing — evens out vignetting and dust shadows.',
            ),
            frames: flats,
            onPick: () => onPick(CalibrationSlot.flat),
            onClear: () => onClear(CalibrationSlot.flat),
          ),
          if (darks.isEmpty && flats.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              tr(
                zh: '不选也能叠 —— 校准帧是给「同一台手机、同一晚、噪点特别脏」这种情况准备的。',
                en: 'Optional: stacks work fine without them. Calibration is for the nights when one phone\'s sensor noise is the thing holding the picture back.',
              ),
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _CalibrationRow extends StatelessWidget {
  const _CalibrationRow({
    required this.icon,
    required this.title,
    required this.hint,
    required this.frames,
    required this.onPick,
    required this.onClear,
  });

  final IconData icon;
  final String title;
  final String hint;
  final List<SourceFrame> frames;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final chosen = frames.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: chosen ? cs.primary : cs.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleSmall),
              const SizedBox(height: 3),
              Text(
                chosen
                    ? tr(zh: '已选 ${frames.length} 张', en: '${frames.length} selected')
                    : hint,
                style: text.bodySmall?.copyWith(
                    color: chosen ? cs.primary : cs.onSurfaceVariant, height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // The theme stretches filled buttons to the full width; these two sit
        // in a row, so they opt back out with an explicit minimum size.
        chosen
            ? IconButton(
                tooltip: tr(zh: '清除', en: 'Clear'),
                onPressed: onClear,
                icon: const Icon(Icons.close),
              )
            : TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(56, 40)),
                onPressed: onPick,
                child: Text(tr(zh: '选择', en: 'Pick')),
              ),
      ],
    );
  }
}

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
