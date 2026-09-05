import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../engine/jobs.dart';
import '../engine/output.dart';
import '../engine/picker.dart';
import '../engine/resize_math.dart';
import '../models.dart';
import '../pro.dart';
import '../store.dart';
import 'result_screen.dart';
import 'widgets.dart';

/// Per-run facts handed to every [RunOne] call.
class RunContext {
  RunContext({required this.outDir, required this.meta});
  final String outDir;
  final ToolMeta meta;
  final Set<String> _taken = {};

  /// Unique output path for [s] with extension [ext] (no dot).
  String pathFor(SourceImage s, String ext) =>
      '$outDir/${outputFileName(s.stem, meta.suffix, ext, _taken)}';
}

typedef RunOne = Future<JobResult> Function(SourceImage src, RunContext ctx);
typedef ImagesBuilder = Widget Function(BuildContext context, List<SourceImage> images);

/// The shared skeleton of every tool screen: header → picked images →
/// optional preview → options → hero "Process" button; then the progress
/// sheet and the result screen. Tools only supply their options widget and
/// a per-image [runOne].
class ToolScaffold extends StatefulWidget {
  const ToolScaffold({
    super.key,
    required this.kind,
    required this.store,
    required this.options,
    required this.runOne,
    this.preview,
    this.blocker,
    this.onImagesChanged,
    this.onBeforeRun,
    this.actions = const [],
  });

  final ToolKind kind;
  final PicboxStore store;

  /// Options panel. Rebuilt whenever the image list changes.
  final ImagesBuilder options;

  /// Optional large preview shown above the options (crop editor,
  /// watermark preview).
  final ImagesBuilder? preview;

  /// Non-null = the start button is disabled and this text explains why.
  final String? blocker;
  final RunOne runOne;
  final ValueChanged<List<SourceImage>>? onImagesChanged;

  /// Called right before processing starts (persist settings, etc.).
  final VoidCallback? onBeforeRun;

  /// Extra app-bar actions.
  final List<Widget> actions;

  @override
  State<ToolScaffold> createState() => _ToolScaffoldState();
}

class _ToolScaffoldState extends State<ToolScaffold> {
  final List<SourceImage> _images = [];
  final ImageImporter _importer = ImageImporter();
  bool _importing = false;
  bool _running = false;

  ToolMeta get meta => ToolMeta.of(widget.kind);

  Future<void> _import({required bool camera}) async {
    if (_importing) return;
    setState(() => _importing = true);
    final r = camera ? await _importer.captureFromCamera() : await _importer.pickFromLibrary();
    if (!mounted) return;
    setState(() {
      _importing = false;
      _images.addAll(r.images);
    });
    widget.onImagesChanged?.call(List.unmodifiable(_images));
    if (r.error != null) {
      showNotice(context, r.error!,
          action: r.permissionDenied
              ? SnackBarAction(label: tr(zh: '去设置', en: 'Settings'), onPressed: openSystemSettings)
              : null);
    } else if (r.skipped.isNotEmpty) {
      showNotice(
          context,
          '${tr(zh: '已跳过', en: 'Skipped')} ${r.skipped.length}: ${r.skipped.first}'
          '${r.skipped.length > 1 ? ' …' : ''}');
    }
  }

  void _remove(SourceImage s) {
    setState(() => _images.removeWhere((e) => e.id == s.id));
    widget.onImagesChanged?.call(List.unmodifiable(_images));
  }

  void _clear() {
    setState(_images.clear);
    widget.onImagesChanged?.call(const []);
  }

  Future<void> _run() async {
    if (_images.isEmpty || _running) return; // double-tap guard
    _running = true;
    try {
      await _runBatch();
    } finally {
      _running = false;
    }
  }

  Future<void> _runBatch() async {
    if (_images.length > kFreeBatchLimit && !widget.store.pro) {
      await showProSheet(context,
          reason: tr(
            zh: '免费版每次最多处理 $kFreeBatchLimit 张,你选了 ${_images.length} 张。解锁 Pro 后不限张数。',
            en: 'The free version handles up to $kFreeBatchLimit images per run; you picked ${_images.length}. Pro removes the cap.',
          ));
      return;
    }
    widget.onBeforeRun?.call();
    final dir = await WorkDirs.fresh('out');
    final ctx = RunContext(outDir: dir.path, meta: meta);
    final batch = List<SourceImage>.from(_images);
    final progress = ValueNotifier<_Progress>(_Progress(0, batch.length, batch.first.name));
    var cancelled = false;
    if (!mounted) return;
    // The sheet is not dismissible by tapping outside; cancel stops after
    // the current image (the isolate finishes its picture, then we stop).
    unawaited(showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _ProgressSheet(progress: progress, onCancel: () => cancelled = true),
    ));
    final results = <JobResult>[];
    for (var i = 0; i < batch.length; i++) {
      if (cancelled) break;
      final src = batch[i];
      progress.value = _Progress(i, batch.length, src.name);
      JobResult r;
      try {
        r = await widget.runOne(src, ctx);
      } catch (e) {
        r = JobResult(source: src, error: describeJobError(e));
      }
      results.add(r);
    }
    progress.value = _Progress(batch.length, batch.length, '');
    if (!mounted) return;
    Navigator.of(context).pop(); // progress sheet
    if (results.isEmpty) return;
    widget.store.addProcessed(results.where((r) => r.ok).length);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultScreen(meta: meta, results: results, cancelled: cancelled),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = _images.fold<int>(0, (a, b) => a + b.bytes);
    final canRun = _images.isNotEmpty && widget.blocker == null && !_importing;
    return Scaffold(
      appBar: AppBar(
        title: Text(meta.title),
        actions: [
          ...widget.actions,
          if (_images.isNotEmpty)
            IconButton(
              tooltip: tr(zh: '清空', en: 'Clear'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clear,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                _Header(meta: meta),
                const SizedBox(height: 16),
                if (_images.isEmpty)
                  _EmptyPicker(
                    meta: meta,
                    busy: _importing,
                    onPick: () => _import(camera: false),
                    onCamera: () => _import(camera: true),
                  )
                else
                  _ImageStrip(
                    images: _images,
                    busy: _importing,
                    onAdd: () => _import(camera: false),
                    onCamera: () => _import(camera: true),
                    onRemove: _remove,
                    pro: widget.store.pro,
                  ),
                if (_images.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      tr(
                        zh: '${_images.length} 张 · 共 ${formatBytes(total)}',
                        en: '${_images.length} image${_images.length == 1 ? '' : 's'} · ${formatBytes(total)} total',
                      ),
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
                if (widget.preview != null && _images.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  widget.preview!(context, List.unmodifiable(_images)),
                ],
                const SizedBox(height: 16),
                widget.options(context, List.unmodifiable(_images)),
                if (widget.blocker != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(widget.blocker!,
                            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: canRun ? _run : null,
                style: FilledButton.styleFrom(backgroundColor: canRun ? meta.color : null),
                icon: Icon(meta.icon),
                label: Text(_images.isEmpty
                    ? tr(zh: '先选择图片', en: 'Pick images first')
                    : tr(zh: '开始处理 ${_images.length} 张', en: 'Process ${_images.length}')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.meta});
  final ToolMeta meta;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [meta.color, meta.color.withValues(alpha: 0.65)],
            ),
          ),
          child: Icon(meta.icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(meta.subtitle, style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _EmptyPicker extends StatelessWidget {
  const _EmptyPicker({required this.meta, required this.busy, required this.onPick, required this.onCamera});
  final ToolMeta meta;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cs.surfaceContainerHigh,
        border: Border.all(color: meta.color.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: meta.color.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.add_photo_alternate_outlined, size: 34, color: meta.color),
          ),
          const SizedBox(height: 14),
          Text(tr(zh: '选几张图片开始', en: 'Pick some pictures to begin'), style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            tr(
              zh: '可多选 · 免费版每次最多 $kFreeBatchLimit 张 · 图片不会离开手机',
              en: 'Multi-select · free: up to $kFreeBatchLimit per run · nothing leaves the phone',
            ),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: busy ? null : onPick,
                  icon: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.photo_library_outlined),
                  label: Text(tr(zh: '从相册选择', en: 'From library')),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: busy ? null : onCamera,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(tr(zh: '拍摄', en: 'Take photo')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({
    required this.images,
    required this.busy,
    required this.onAdd,
    required this.onCamera,
    required this.onRemove,
    required this.pro,
  });
  final List<SourceImage> images;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onCamera;
  final ValueChanged<SourceImage> onRemove;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (i, s) in images.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Tooltip(message: '${s.name}\n${describeImage(s)}', child: ImageThumb(path: s.path, size: 84, radius: 14)),
                  if (!pro && i >= kFreeBatchLimit)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                        child: const Icon(Icons.lock_outline, color: Colors.white),
                      ),
                    ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Material(
                      color: cs.inverseSurface,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onRemove(s),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 14, color: cs.onInverseSurface),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _AddTile(icon: Icons.add_photo_alternate_outlined, onTap: busy ? null : onAdd, busy: busy),
          const SizedBox(width: 8),
          _AddTile(icon: Icons.photo_camera_outlined, onTap: busy ? null : onCamera, busy: false),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.icon, required this.onTap, required this.busy});
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 84,
          height: 84,
          child: busy
              ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : Icon(icon, color: cs.primary),
        ),
      ),
    );
  }
}

class _Progress {
  const _Progress(this.done, this.total, this.current);
  final int done;
  final int total;
  final String current;
}

class _ProgressSheet extends StatelessWidget {
  const _ProgressSheet({required this.progress, required this.onCancel});
  final ValueNotifier<_Progress> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: ValueListenableBuilder<_Progress>(
            valueListenable: progress,
            builder: (context, p, _) {
              final frac = p.total == 0 ? 0.0 : p.done / p.total;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(tr(zh: '正在处理…', en: 'Processing…'), style: text.titleMedium),
                      ),
                      Text('${p.done} / ${p.total}',
                          style: text.titleMedium?.copyWith(
                              fontFeatures: const [FontFeature.tabularFigures()])),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(value: frac, minHeight: 10),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    p.current.isEmpty ? tr(zh: '收尾中', en: 'Finishing') : p.current,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onCancel,
                      child: Text(tr(zh: '完成当前这张后停止', en: 'Stop after this one')),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
