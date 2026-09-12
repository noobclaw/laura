import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../engine/output.dart';
import '../engine/resize_math.dart';
import '../models.dart';
import 'widgets.dart';

/// Results of one run: per-image before/after rows, a save-to-Photos hero
/// button and a share button. Tapping a row opens the swipe comparison.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.meta, required this.results, this.cancelled = false});
  final ToolMeta meta;
  final List<JobResult> results;
  final bool cancelled;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _saving = false;
  bool _saved = false;
  bool _sharing = false;

  int get _okCount => widget.results.where((r) => r.ok).length;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final o = await saveResultsToPhotos(widget.results);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = o.saved > 0;
    });
    if (o.error != null) {
      showNotice(context, o.error!,
          action: o.permanentlyDenied
              ? SnackBarAction(label: tr(zh: '去设置', en: 'Settings'), onPressed: openSystemSettings)
              : null);
    } else if (o.failed > 0) {
      showNotice(context, tr(zh: '已保存 ${o.saved} 张,${o.failed} 张失败', en: 'Saved ${o.saved}, ${o.failed} failed'));
    } else {
      showNotice(context, tr(zh: '已保存 ${o.saved} 张到相册', en: 'Saved ${o.saved} to Photos'));
    }
  }

  Future<void> _share(BuildContext btnContext) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final err = await shareResults(widget.results, origin: shareOriginOf(btnContext));
      if (err != null && mounted) showNotice(context, err);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final before = widget.results.fold<int>(0, (a, r) => a + r.source.bytes);
    final after = widget.results.fold<int>(0, (a, r) => a + (r.outputBytes ?? r.source.bytes));
    final failed = widget.results.length - _okCount;
    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '处理结果', en: 'Results'))),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                _Summary(
                  meta: widget.meta,
                  ok: _okCount,
                  failed: failed,
                  before: before,
                  after: after,
                  cancelled: widget.cancelled,
                ),
                const SizedBox(height: 16),
                for (final (i, r) in widget.results.indexed) ...[
                  _Enter(
                    delay: Duration(milliseconds: 60 * (i < 8 ? i : 8)),
                    child: _ResultRow(result: r, meta: widget.meta),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                Text(
                  tr(
                    zh: '结果先放在应用的临时目录里;保存到相册或分享后才会离开应用。',
                    en: 'Results sit in the app\'s temporary folder until you save or share them.',
                  ),
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _okCount == 0 || _saving ? null : _save,
                      child: AnimatedSwitcher(
                        duration: Motion.of(context, Motion.normal),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(anim), child: child),
                        ),
                        child: Row(
                          key: ValueKey(_saving ? 'saving' : (_saved ? 'saved' : 'save')),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_saving)
                              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            else
                              Icon(_saved ? Icons.check_rounded : Icons.save_alt_rounded, size: 20),
                            const SizedBox(width: 8),
                            Text(_saved
                                ? tr(zh: '已保存', en: 'Saved')
                                : tr(zh: '保存到相册 ($_okCount)', en: 'Save to Photos ($_okCount)')),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Builder(
                    builder: (btnCtx) => OutlinedButton.icon(
                      onPressed: _okCount == 0 || _sharing ? null : () => _share(btnCtx),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                      icon: const Icon(Icons.ios_share_rounded),
                      label: Text(tr(zh: '分享', en: 'Share')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.meta,
    required this.ok,
    required this.failed,
    required this.before,
    required this.after,
    required this.cancelled,
  });
  final ToolMeta meta;
  final int ok;
  final int failed;
  final int before;
  final int after;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pct = before == 0 ? 0 : ((1 - after / before) * 100).round();
    final dur = Motion.of(context, Motion.count);
    final showSize = meta.kind == ToolKind.compress ||
        meta.kind == ToolKind.resize ||
        meta.kind == ToolKind.convert ||
        meta.kind == ToolKind.metadata;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [meta.color, meta.color.withValues(alpha: 0.7)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(failed == 0 && !cancelled ? Icons.check_circle_rounded : Icons.info_rounded,
                  color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                // "N done" counts up from 0 (PIPELINE #10 ③).
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: ok.toDouble()),
                  duration: dur,
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) {
                    final n = v.round();
                    return Text(
                      cancelled
                          ? tr(zh: '已停止 · 完成 $n 张', en: 'Stopped · $n done')
                          : failed == 0
                              ? tr(zh: '完成 $n 张', en: '$n done')
                              : tr(zh: '完成 $n 张,$failed 张失败', en: '$n done, $failed failed'),
                      style: text.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                    );
                  },
                ),
              ),
            ],
          ),
          if (showSize) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatBytes(before),
                    style: text.titleLarge?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, color: Colors.white.withValues(alpha: 0.9), size: 20),
                ),
                // The "after" size shrinks from the "before" size, and the
                // saved-percent pill counts up alongside it.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: before.toDouble(), end: after.toDouble()),
                  duration: dur,
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Text(formatBytes(v.round()),
                      style: text.headlineSmall?.copyWith(color: Colors.white)),
                ),
                const Spacer(),
                if (pct > 0)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: pct.toDouble()),
                    duration: dur,
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('−${v.round()}%',
                          style: text.labelLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result, required this.meta});
  final JobResult result;
  final ToolMeta meta;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final r = result;
    final s = r.source;
    final ok = r.ok;
    final sizeLine = ok
        ? '${formatBytes(s.bytes)} → ${formatBytes(r.outputBytes ?? 0)}'
        : formatBytes(s.bytes);
    final dimLine = ok && r.outputWidth != null
        ? (r.outputWidth == s.width && r.outputHeight == s.height
            ? '${s.width}×${s.height}'
            : '${s.width}×${s.height} → ${r.outputWidth}×${r.outputHeight}')
        : '${s.width}×${s.height}';
    final fmtLine = ok && r.outputFormat != null && r.outputFormat != s.shownFormat
        ? '${s.shownFormat.label} → ${r.outputFormat!.label}'
        : s.shownFormat.label;
    final pct = ok && r.outputBytes != null && s.bytes > 0
        ? ((1 - r.outputBytes! / s.bytes) * 100).round()
        : null;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: ok
            ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CompareScreen(result: r),
                ))
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ImageThumb(path: ok ? r.outputPath! : s.path, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(ok ? '$sizeLine · $fmtLine' : r.error!,
                        maxLines: 2,
                        style: text.bodySmall?.copyWith(color: ok ? cs.onSurfaceVariant : cs.error)),
                    if (ok)
                      Text(r.note != null ? '$dimLine · ${r.note}' : dimLine,
                          maxLines: 2, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (pct != null && pct != 0)
                Text(pct > 0 ? '−$pct%' : '+${-pct}%',
                    style: text.labelLarge?.copyWith(
                        color: pct > 0 ? ToolColors.compress : cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()]))
              else if (ok)
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen before/after: drag the divider to reveal either side.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key, required this.result});
  final JobResult result;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  double _split = 0.5;
  bool _sideBySide = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(r.source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: tr(zh: '切换对比方式', en: 'Toggle layout'),
            icon: Icon(_sideBySide ? Icons.compare_rounded : Icons.view_column_rounded),
            onPressed: () => setState(() => _sideBySide = !_sideBySide),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _sideBySide
                ? Row(
                    children: [
                      Expanded(child: _Labelled(label: tr(zh: '原图', en: 'Before'), child: Image.file(File(r.source.path), fit: BoxFit.contain, cacheWidth: _compareCacheWidth(context)))),
                      const SizedBox(width: 2),
                      Expanded(child: _Labelled(label: tr(zh: '处理后', en: 'After'), child: Image.file(File(r.outputPath!), fit: BoxFit.contain, cacheWidth: _compareCacheWidth(context)))),
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, c) => GestureDetector(
                      onHorizontalDragStart: (_) => setState(() => _dragging = true),
                      onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                      onHorizontalDragCancel: () => setState(() => _dragging = false),
                      onHorizontalDragUpdate: (d) =>
                          setState(() => _split = (_split + d.delta.dx / c.maxWidth).clamp(0.02, 0.98)),
                      onTapDown: (d) => setState(() => _split = (d.localPosition.dx / c.maxWidth).clamp(0.02, 0.98)),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(r.outputPath!), fit: BoxFit.contain, cacheWidth: _compareCacheWidth(context)),
                          ClipRect(
                            clipper: _LeftClipper(_split),
                            child: Image.file(File(r.source.path), fit: BoxFit.contain, cacheWidth: _compareCacheWidth(context)),
                          ),
                          // Divider: lights up lime while the finger is on it.
                          Positioned(
                            left: c.maxWidth * _split - 1,
                            top: 0,
                            bottom: 0,
                            child: AnimatedContainer(
                              duration: Motion.of(context, Motion.fast),
                              width: 2,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: ToolColors.compress.withValues(alpha: _dragging ? 0.9 : 0),
                                    blurRadius: _dragging ? 14 : 0,
                                    spreadRadius: _dragging ? 2 : 0,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: c.maxWidth * _split - 18,
                            top: c.maxHeight / 2 - 18,
                            child: AnimatedScale(
                              scale: _dragging ? 1.18 : 1,
                              duration: Motion.of(context, Motion.fast),
                              curve: Curves.easeOut,
                              child: AnimatedContainer(
                                duration: Motion.of(context, Motion.fast),
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _dragging ? ToolColors.compress : Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6),
                                    if (_dragging)
                                      BoxShadow(color: ToolColors.compress.withValues(alpha: 0.6), blurRadius: 18, spreadRadius: 2),
                                  ],
                                ),
                                child: Icon(Icons.unfold_more_rounded,
                                    color: _dragging ? Colors.white : Colors.black87),
                              ),
                            ),
                          ),
                          Positioned(left: 12, top: 12, child: _Tag(tr(zh: '原图', en: 'Before'))),
                          Positioned(right: 12, top: 12, child: _Tag(tr(zh: '处理后', en: 'After'))),
                        ],
                      ),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: tr(zh: '原图', en: 'Before'),
                      value: '${formatBytes(r.source.bytes)}\n${r.source.width}×${r.source.height}',
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, color: cs.onSurfaceVariant),
                  Expanded(
                    child: _Stat(
                      label: tr(zh: '处理后', en: 'After'),
                      value: '${formatBytes(r.outputBytes ?? 0)}\n${r.outputWidth ?? '?'}×${r.outputHeight ?? '?'}',
                      style: text.titleMedium?.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Decode the two compare images at screen width, not at full resolution.
/// The compare page holds the original AND the result at once; a pair of 48 MP
/// iPhone originals decoded raw is ~190 MB each, which is a jetsam kill with
/// no crash dialog. Every other Image.file in this app already passes
/// cacheWidth — these four were the only ones that did not.
int _compareCacheWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();

class _LeftClipper extends CustomClipper<Rect> {
  const _LeftClipper(this.frac);
  final double frac;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * frac, size.height);
  @override
  bool shouldReclip(_LeftClipper old) => old.frac != frac;
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      );
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [child, Positioned(left: 8, top: 8, child: _Tag(label))],
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.style});
  final String label;
  final String value;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(label, style: text.labelSmall?.copyWith(color: Colors.white60)),
        const SizedBox(height: 2),
        Text(value,
            textAlign: TextAlign.center,
            style: style ??
                text.titleMedium?.copyWith(color: Colors.white70, fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }
}

/// Slide-and-fade a child in after [delay]; used to stagger the result rows.
class _Enter extends StatefulWidget {
  const _Enter({required this.delay, required this.child});
  final Duration delay;
  final Widget child;

  @override
  State<_Enter> createState() => _EnterState();
}

class _EnterState extends State<_Enter> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.slow);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  bool _kicked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_kicked) return;
    _kicked = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(_a),
        child: widget.child,
      ),
    );
  }
}
