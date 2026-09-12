import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'compare_slider.dart';
import 'job_runner.dart';
import 'media.dart';
import 'models.dart';
import 'pro.dart';
import 'store.dart';

/// The before/after view for one result, with save / share / delete.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.record,
    required this.store,
    required this.fresh,
  });

  final LiftRecord record;
  final PhotoLiftStore store;
  /// Just produced (title says so) vs. opened from history.
  final bool fresh;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

enum _View { compare, zoom }

class _ResultScreenState extends State<ResultScreen> {
  _View _view = _View.compare;
  bool _busy = false;
  /// The compare divider sweeps once per visit, not every time the user
  /// flips between compare and zoom.
  bool _swept = false;

  LiftRecord get r => widget.record;
  File get _out => File(widget.store.outputPath(r));
  File get _src => File(widget.store.sourcePath(r));

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final stamp = r.createdAt.toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first;
      await MediaBridge.saveToGallery(_out.path, displayName: 'PixelLift_${stamp}_${r.scale}x.jpg');
      if (!mounted) return;
      _snack(tr(zh: '已保存到相册', en: 'Saved to Photos'));
    } on MediaException catch (e) {
      if (!mounted) return;
      if (e.code == 'permission_denied') {
        _snack(
          tr(zh: '没有写入相册的权限,请在系统设置里允许「添加照片」。',
              en: 'Permission to add to Photos was denied — allow "Add Photos" in Settings.'),
          action: SnackBarAction(
              label: tr(zh: '去设置', en: 'Settings'), onPressed: MediaBridge.openSettings),
        );
      } else {
        _snack(describeUpscaleError(e));
      }
    } catch (e) {
      if (mounted) _snack(describeUpscaleError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(BuildContext btnContext) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // iPad presents the share sheet as a popover and needs an origin rect.
      final box = btnContext.findRenderObject() as RenderBox?;
      final origin = box != null && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(_out.path, mimeType: 'image/jpeg')],
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      if (mounted) _snack(tr(zh: '分享失败:$e', en: 'Share failed: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '删除这条记录?', en: 'Delete this result?')),
        content: Text(tr(
          zh: '会删除应用内的原图副本和修复结果;已保存到相册的照片不受影响。',
          en: 'Removes the in-app source copy and result; anything already saved to Photos stays.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(zh: '取消', en: 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(zh: '删除', en: 'Delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.store.deleteRecord(r);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final aspect = r.outWidth > 0 && r.outHeight > 0 ? r.outWidth / r.outHeight : 4 / 3;
    final missing = !_out.existsSync();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fresh
            ? tr(zh: '修复完成', en: 'Restored')
            : tr(zh: '修复结果', en: 'Result')),
        actions: [
          IconButton(
            tooltip: tr(zh: '删除', en: 'Delete'),
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : _delete,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            if (missing)
              _MissingCard()
            else ...[
              SegmentedButton<_View>(
                segments: [
                  ButtonSegment(
                      value: _View.compare,
                      icon: const Icon(Icons.compare),
                      label: Text(tr(zh: '前后对比', en: 'Compare'))),
                  ButtonSegment(
                      value: _View.zoom,
                      icon: const Icon(Icons.zoom_in),
                      label: Text(tr(zh: '放大细看', en: 'Zoom'))),
                ],
                selected: {_view},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
              const SizedBox(height: 12),
              if (_view == _View.compare)
                CompareSlider(
                  before: _src,
                  after: _out,
                  aspectRatio: aspect.clamp(0.4, 2.5),
                  autoSweep: !_swept,
                  onSweepEnd: () => _swept = true,
                )
              else
                _ZoomView(file: _out, aspectRatio: aspect.clamp(0.4, 2.5)),
              const SizedBox(height: 8),
              Text(
                _view == _View.compare
                    ? tr(zh: '左右拖动分界线对比', en: 'Drag the divider to compare')
                    : tr(zh: '双指缩放查看细节', en: 'Pinch to inspect the detail'),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            if (r.engine == EngineKind.dartFallback) ...[
              _Notice(
                icon: Icons.info_outline,
                color: cs.tertiaryContainer,
                onColor: cs.onTertiaryContainer,
                text: tr(
                  zh: '这次用的是基础放大(此设备上 AI 引擎不可用),效果会弱于 AI 修复。',
                  en: 'This result used basic resampling — the AI engine is not available on this device, so it is weaker than an AI restore.',
                ),
              ),
              const SizedBox(height: 12),
            ],
            _StatsStrip(record: r, animate: widget.fresh || !_swept),
            if (r.tagged && !widget.store.pro) ...[
              const SizedBox(height: 12),
              _Notice(
                icon: Icons.sell_outlined,
                color: cs.surfaceContainerHigh,
                onColor: cs.onSurfaceVariant,
                text: tr(
                  zh: '右下角有一个小小的 PixelLift 标签。升级 Pro 后不再添加。',
                  en: 'A small PixelLift tag sits in the bottom-right corner. Pro results carry no tag.',
                ),
                action: TextButton(
                  onPressed: () => showProSheet(context),
                  child: Text(tr(zh: '了解 Pro', en: 'About Pro')),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (!missing)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_alt),
                      label: Text(tr(zh: '保存到相册', en: 'Save to Photos')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Builder(
                      builder: (btnCtx) => OutlinedButton.icon(
                        onPressed: _busy ? null : () => _share(btnCtx),
                        icon: const Icon(Icons.ios_share),
                        label: Text(tr(zh: '分享', en: 'Share')),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomView extends StatelessWidget {
  const _ZoomView({required this.file, required this.aspectRatio});
  final File file;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: cs.surfaceContainerHighest,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            // Full-resolution decode: the whole point of this view.
            child: Image.file(file, fit: BoxFit.contain, filterQuality: FilterQuality.high),
          ),
        ),
      ),
    );
  }
}

/// Time / scale / resolution as three counters that roll up to their values
/// on arrival (TweenAnimationBuilder), plus the denoise + engine caption.
/// The resolution counts from the input size to the output size — the
/// number literally grows.
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.record, required this.animate});
  final LiftRecord record;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final r = record;
    final zh = isZhLocale;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final dur = animate && !reduce
        ? const Duration(milliseconds: 900)
        : Duration.zero;
    String fmtSecs(double v) {
      if (v < 60) return zh ? '${v.toStringAsFixed(1)} 秒' : '${v.toStringAsFixed(1)} s';
      final m = v ~/ 60;
      final sec = (v - m * 60).round();
      return zh ? '$m 分 $sec 秒' : '${m}m ${sec}s';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: tr(zh: '用时', en: 'Time'),
                    duration: dur,
                    end: r.elapsedMs / 1000,
                    format: fmtSecs,
                  ),
                ),
                _vDivider(cs),
                Expanded(
                  child: _StatTile(
                    label: tr(zh: '放大倍数', en: 'Upscale'),
                    duration: dur,
                    end: r.scale.toDouble(),
                    format: (v) => '${v.round()}x',
                    accent: true,
                  ),
                ),
                _vDivider(cs),
                Expanded(
                  flex: 2,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: animate ? 0.0 : 1.0, end: 1.0),
                    duration: dur,
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) {
                      final w = (r.inWidth + (r.outWidth - r.inWidth) * t).round();
                      final h = (r.inHeight + (r.outHeight - r.inHeight) * t).round();
                      return _StatText(
                        label: tr(zh: '分辨率', en: 'Resolution'),
                        value: '$w × $h',
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${tr(zh: '降噪', en: 'Denoise')} ${r.denoise.label} · '
              '${r.engine.label} · ${r.inWidth} × ${r.inHeight} → ${r.outWidth} × ${r.outHeight}',
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _vDivider(ColorScheme cs) => Container(
        width: 1,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: cs.outlineVariant.withValues(alpha: 0.6),
      );
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.duration,
    required this.end,
    required this.format,
    this.accent = false,
  });
  final String label;
  final Duration duration;
  final double end;
  final String Function(double) format;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: duration == Duration.zero ? end : 0.0, end: end),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => _StatText(label: label, value: format(v), accent: accent),
    );
  }
}

class _StatText extends StatelessWidget {
  const _StatText({required this.label, required this.value, this.accent = false});
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        // Shrink a long figure ("12m 34s", "4000 × 3000") to fit the
        // column instead of cutting it off with an ellipsis.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: accent ? (Theme.of(context).brightness == Brightness.dark ? kLiftGold : cs.primary) : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.onColor,
    required this.text,
    this.action,
  });
  final IconData icon;
  final Color color;
  final Color onColor;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, color: onColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: onColor, height: 1.4))),
          ?action,
        ],
      ),
    );
  }
}

class _MissingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
          color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Icon(Icons.broken_image_outlined, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            tr(zh: '结果文件已不存在(可能被系统清理)。可以删除这条记录。',
                en: 'The result file is gone (the system may have cleaned it up). You can delete this entry.'),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
