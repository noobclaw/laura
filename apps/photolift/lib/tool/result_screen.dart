import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/l10n.dart';
import 'compare_slider.dart';
import 'eta.dart';
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
      await MediaBridge.saveToGallery(_out.path, displayName: 'PhotoLift_${stamp}_${r.scale}x.jpg');
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
                CompareSlider(before: _src, after: _out, aspectRatio: aspect.clamp(0.4, 2.5))
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
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                child: Column(
                  children: [
                    _Row(tr(zh: '放大', en: 'Upscale'), '${r.scale}x · ${tr(zh: '降噪', en: 'denoise')} ${r.denoise.label}'),
                    _Row(tr(zh: '尺寸', en: 'Size'), '${r.inWidth} × ${r.inHeight}  →  ${r.outWidth} × ${r.outHeight}'),
                    _Row(tr(zh: '引擎', en: 'Engine'), '${r.engine.label} · ${formatEta(r.elapsedMs / 1000, zh: isZhLocale)}'),
                  ],
                ),
              ),
            ),
            if (r.tagged && !widget.store.pro) ...[
              const SizedBox(height: 12),
              _Notice(
                icon: Icons.sell_outlined,
                color: cs.surfaceContainerHigh,
                onColor: cs.onSurfaceVariant,
                text: tr(
                  zh: '右下角有一个小小的 PhotoLift 标签。升级 Pro 后不再添加。',
                  en: 'A small PhotoLift tag sits in the bottom-right corner. Pro results carry no tag.',
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

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 64,
              child: Text(label, style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
          Expanded(
              child: Text(value,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
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
