import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'export.dart';
import 'geo_format.dart';
import 'models.dart';
import 'motion.dart';
import 'pro.dart';
import 'store.dart';

/// Local archive for the current project: a photo grid grouped by date, with a
/// multi-select mode for exporting a PDF report / CSV ledger / sharing images.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.store});

  final FieldStampStore store;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _busy = false;

  /// What the [AnimatedGrid] currently shows. Kept in step with the store by
  /// diffing on every notification: new photos animate in at their slot,
  /// deleted ones animate out. A project switch resets the grid outright.
  final List<StampPhoto> _shown = [];
  String? _shownProject;
  GlobalKey<AnimatedGridState> _gridKey = GlobalKey<AnimatedGridState>();

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_syncGrid);
    _syncGrid();
  }

  @override
  void dispose() {
    widget.store.removeListener(_syncGrid);
    super.dispose();
  }

  void _syncGrid() {
    final store = widget.store;
    final target = store.photosForProject(store.currentProjectId);
    final grid = _gridKey.currentState;
    if (grid == null || _shownProject != store.currentProjectId) {
      _shown
        ..clear()
        ..addAll(target);
      _shownProject = store.currentProjectId;
      _gridKey = GlobalKey<AnimatedGridState>();
      return;
    }
    final targetIds = {for (final p in target) p.id};
    for (var i = _shown.length - 1; i >= 0; i--) {
      if (targetIds.contains(_shown[i].id)) continue;
      final gone = _shown.removeAt(i);
      grid.removeItem(
        i,
        (context, anim) => _tile(store, gone, anim, ghost: true),
        duration: Motion.of(context, 220),
      );
    }
    final shownIds = {for (final p in _shown) p.id};
    for (var i = 0; i < target.length; i++) {
      if (shownIds.contains(target[i].id)) continue;
      _shown.insert(i, target[i]);
      grid.insertItem(i, duration: Motion.of(context, 360));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final photos = store.photosForProject(store.currentProjectId);
        return Column(
          children: [
            _header(store, photos),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.of(context, 260),
                switchInCurve: Motion.enter,
                child: photos.isEmpty
                    ? const _EmptyGallery()
                    : _grid(store),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(FieldStampStore store, List<StampPhoto> photos) {
    if (_selecting) {
      return Material(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _selecting = false;
                          _selected.clear();
                        }),
              ),
              Expanded(
                child: Row(
                  children: [
                    _RollingCount(
                        value: _selected.length,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Text(tr(zh: '项已选', en: 'selected'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr(zh: '分享图片', en: 'Share images'),
                icon: const Icon(Icons.ios_share),
                onPressed:
                    _selected.isEmpty || _busy ? null : () => _shareImages(store),
              ),
              IconButton(
                tooltip: tr(zh: 'PDF 报告', en: 'PDF report'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed:
                    _selected.isEmpty || _busy ? null : () => _exportPdf(store),
              ),
              IconButton(
                tooltip: tr(zh: 'CSV 台账', en: 'CSV ledger'),
                icon: const Icon(Icons.table_chart_outlined),
                onPressed:
                    _selected.isEmpty || _busy ? null : () => _exportCsv(store),
              ),
              IconButton(
                tooltip: tr(zh: '删除', en: 'Delete'),
                icon: const Icon(Icons.delete_outline),
                onPressed: _selected.isEmpty || _busy
                    ? null
                    : () => _deleteSelected(store),
              ),
            ],
          ),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final withFix = photos.where((p) => p.hasFix).length;
    return Material(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store.projectName(store.currentProjectId),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Two live counters: total photos and how many carry a fix.
                  Row(
                    children: [
                      _RollingCount(
                        value: photos.length,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium!
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 4),
                      Text(tr(zh: '张照片', en: 'photos'),
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12)),
                      const SizedBox(width: 12),
                      Icon(Icons.gps_fixed,
                          size: 13,
                          color: withFix == photos.length && photos.isNotEmpty
                              ? cs.primary
                              : Motion.safetyOrange),
                      const SizedBox(width: 4),
                      _RollingCount(
                        value: withFix,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium!
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 4),
                      Text(tr(zh: '含 GPS', en: 'with GPS'),
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            if (photos.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.checklist, size: 18),
                label: Text(tr(zh: '选择', en: 'Select')),
                onPressed: () => setState(() => _selecting = true),
              ),
          ],
        ),
      ),
    );
  }

  Widget _grid(FieldStampStore store) {
    return AnimatedGrid(
      key: _gridKey,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      initialItemCount: _shown.length,
      // The grid can be asked for an index one past the list for a frame
      // while a removal is still animating; never index out of range.
      itemBuilder: (context, i, anim) => i >= _shown.length
          ? const SizedBox.shrink()
          : _tile(store, _shown[i], anim),
    );
  }

  /// One grid cell. Enters with a fade + scale-up; when [ghost] it is the
  /// outgoing copy of a deleted photo, driven by the reverse of [anim].
  Widget _tile(FieldStampStore store, StampPhoto p, Animation<double> anim,
      {bool ghost = false}) {
    final selected = _selected.contains(p.id);
    // `drive` creates no listener-holding CurvedAnimation to dispose of.
    final curved = anim.drive(CurveTween(curve: Motion.enter));
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.82, end: 1).animate(curved),
        child: GestureDetector(
          onTap: ghost
              ? null
              : () {
                  if (_selecting) {
                    setState(() {
                      if (selected) {
                        _selected.remove(p.id);
                      } else {
                        _selected.add(p.id);
                      }
                    });
                  } else {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PhotoDetailScreen(
                          store: store, photo: p, heroTag: 'photo-${p.id}'),
                    ));
                  }
                },
          onLongPress: ghost
              ? null
              : () => setState(() {
                    _selecting = true;
                    _selected.add(p.id);
                  }),
          child: AnimatedContainer(
            duration: Motion.of(context, 180),
            curve: Motion.standard,
            padding: EdgeInsets.all(selected ? 6 : 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(selected ? 8 : 12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ghost
                      ? _thumb(store, p, ghost: true)
                      : Hero(
                          tag: 'photo-${p.id}',
                          // Both the tile left behind and the shuttle in
                          // flight show the already-decoded 300 px thumbnail
                          // instead of an empty box while the full-size
                          // image on the detail page is still decoding.
                          placeholderBuilder: (_, _, _) => _thumb(store, p),
                          flightShuttleBuilder: (_, _, _, _, _) => Image(
                            image: thumbProviderFor(
                                File(store.photoPath(p.fileName))),
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                          ),
                          child: _thumb(store, p),
                        ),
                  if (!p.hasFix)
                    const Positioned(
                      left: 4,
                      top: 4,
                      child: Icon(Icons.gps_off,
                          size: 16, color: Motion.safetyOrange),
                    ),
                  if (_selecting)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: AnimatedSwitcher(
                        duration: Motion.of(context, 160),
                        switchInCurve: Curves.easeOutBack,
                        transitionBuilder: (child, a) =>
                            ScaleTransition(scale: a, child: child),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          key: ValueKey(selected),
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white70,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 4)
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The 300 px grid thumbnail. A [ghost] (a deleted photo animating out)
  /// skips the existence check: the store removes the file before it
  /// notifies, so the check would fail and replace the outgoing image with a
  /// broken-image glyph. The decoded thumbnail is still in the image cache
  /// under the same key, so `Image` shows it; if the cache was evicted, a
  /// plain grey cell is the fallback rather than a "broken" icon.
  Widget _thumb(FieldStampStore store, StampPhoto p, {bool ghost = false}) {
    final file = File(store.photoPath(p.fileName));
    return Container(
      color: Colors.black12,
      child: ghost || file.existsSync()
          ? Image.file(
              file,
              fit: BoxFit.cover,
              cacheWidth: 300,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => ghost
                  ? const ColoredBox(color: Colors.black12)
                  : const Icon(Icons.broken_image_outlined),
            )
          : const Icon(Icons.broken_image_outlined),
    );
  }

  List<StampPhoto> _selectedPhotos(FieldStampStore store) {
    final all = store.photosForProject(store.currentProjectId);
    return all.where((p) => _selected.contains(p.id)).toList();
  }

  bool _enforceLimit(FieldStampStore store, int count) {
    if (store.pro || count <= FieldStampStore.freeExportLimit) return true;
    showProSheet(context,
        reason: tr(
            zh: '免费版报告最多包含 ${FieldStampStore.freeExportLimit} 张照片,Pro 不限量。',
            en: 'Free reports are limited to ${FieldStampStore.freeExportLimit} photos; Pro has no cap.'));
    return false;
  }

  Future<void> _shareImages(FieldStampStore store) async {
    final photos = _selectedPhotos(store);
    if (photos.isEmpty) return;
    final origin = shareOriginOf(context);
    setState(() => _busy = true);
    try {
      await sharePhotos(photos, store, origin: origin);
    } catch (e) {
      _snack(tr(zh: '分享失败:$e', en: 'Share failed: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPdf(FieldStampStore store) async {
    final photos = _selectedPhotos(store);
    if (photos.isEmpty) return;
    if (!store.pro) {
      _proNeeded(tr(zh: 'PDF 报告', en: 'PDF report'));
      return;
    }
    if (!_enforceLimit(store, photos.length)) return;
    final origin = shareOriginOf(context);
    setState(() => _busy = true);
    try {
      final bytes = await buildPdf(photos, store);
      final name = _fileStamp('fieldstamp-report', 'pdf');
      await shareBytes(bytes, name,
          text: tr(zh: 'FieldStamp 巡检报告', en: 'FieldStamp inspection report'),
          origin: origin);
    } catch (e) {
      _snack(tr(zh: 'PDF 导出失败:$e', en: 'PDF export failed: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv(FieldStampStore store) async {
    final photos = _selectedPhotos(store);
    if (photos.isEmpty) return;
    if (!store.pro) {
      _proNeeded(tr(zh: 'CSV 导出', en: 'CSV export'));
      return;
    }
    if (!_enforceLimit(store, photos.length)) return;
    final origin = shareOriginOf(context);
    setState(() => _busy = true);
    try {
      final csv = buildCsv(photos, store);
      final name = _fileStamp('fieldstamp-ledger', 'csv');
      await shareBytes(utf8.encode(csv), name,
          text: tr(zh: 'FieldStamp CSV 台账', en: 'FieldStamp CSV ledger'),
          origin: origin);
    } catch (e) {
      _snack(tr(zh: 'CSV 导出失败:$e', en: 'CSV export failed: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected(FieldStampStore store) async {
    final photos = _selectedPhotos(store);
    if (photos.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(
            zh: '删除 ${photos.length} 张照片?',
            en: 'Delete ${photos.length} photos?')),
        content: Text(tr(
            zh: '将从此设备上永久删除。',
            en: 'This permanently removes them from this device.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(zh: '取消', en: 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(zh: '删除', en: 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    for (final p in photos) {
      await store.deletePhoto(p);
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _selecting = false;
        _selected.clear();
      });
    }
  }

  void _proNeeded(String feature) {
    showProSheet(context,
        reason: tr(
            zh: '$feature 是 Pro 功能。',
            en: '$feature is a Pro feature.'));
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  String _fileStamp(String prefix, String ext) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '$prefix-${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}.$ext';
  }
}

/// The provider behind every `Image.file(file, cacheWidth: 300)` thumbnail in
/// the grid — the same key, so the Hero shuttle and the detail page's first
/// frame hit the image cache instead of decoding the full photo.
ImageProvider thumbProviderFor(File file) =>
    ResizeImage(FileImage(file), width: 300);

/// Counter that rolls to its new value instead of jumping.
class _RollingCount extends StatelessWidget {
  const _RollingCount({required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: Motion.of(context, 500),
      curve: Motion.standard,
      builder: (context, v, _) => Text(
        v.round().toString(),
        style: style.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A miniature of the viewfinder: brackets + the iris shutter.
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                children: [
                  for (final a in const [
                    Alignment.topLeft,
                    Alignment.topRight,
                    Alignment.bottomLeft,
                    Alignment.bottomRight,
                  ])
                    Align(
                      alignment: a,
                      child: CornerBracket(
                          color: cs.primary, alignment: a, size: 30),
                    ),
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary,
                        border: Border.all(
                            color: Motion.safetyOrange, width: 3),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: CustomPaint(
                        painter: AperturePainter(
                          closure: 0.25,
                          blade: cs.onPrimary,
                          seam: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(tr(zh: '还没有照片', en: 'No photos yet'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              tr(
                  zh: '切换到「相机」标签页,按下快门。\n'
                      '每张照片都会烧入 GPS、时间和方位水印。',
                  en: 'Switch to the Camera tab and tap the shutter.\n'
                      'Each photo is stamped with GPS, time and bearing.'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen view of a single stamped photo plus its metadata.
class PhotoDetailScreen extends StatefulWidget {
  const PhotoDetailScreen({
    super.key,
    required this.store,
    required this.photo,
    this.heroTag,
  });

  final FieldStampStore store;
  final StampPhoto photo;

  /// Matches the Hero on the grid tile that opened this page.
  final Object? heroTag;

  @override
  State<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final p = widget.photo;
    final file = File(store.photoPath(p.fileName));
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(zh: '照片', en: 'Photo')),
        actions: [
          Builder(
            builder: (btnCtx) => IconButton(
              icon: const Icon(Icons.ios_share),
              onPressed: () async {
                try {
                  await sharePhotos([p], store,
                      origin: shareOriginOf(btnCtx));
                } catch (e) {
                  if (!btnCtx.mounted) return;
                  ScaffoldMessenger.of(btnCtx).showSnackBar(SnackBar(
                      content: Text(
                          tr(zh: '分享失败:$e', en: 'Share failed: $e'))));
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(tr(zh: '删除这张照片?', en: 'Delete photo?')),
                  content: Text(
                      tr(zh: '此操作无法撤销。', en: 'This cannot be undone.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(tr(zh: '取消', en: 'Cancel'))),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.error),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(tr(zh: '删除', en: 'Delete')),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await store.deletePhoto(p);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          Container(
            color: Colors.black,
            child: Hero(
              tag: widget.heroTag ?? 'detail-${p.id}',
              child: file.existsSync()
                  ? Image.file(
                      file,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      // Until the full-size frame is decoded, show the
                      // cached grid thumbnail (same aspect, so no jump).
                      frameBuilder: (_, child, frame, syncLoaded) =>
                          frame == null && !syncLoaded
                              ? Image(
                                  image: thumbProviderFor(file),
                                  fit: BoxFit.contain,
                                  excludeFromSemantics: true,
                                )
                              : child,
                    )
                  : const SizedBox(
                      height: 240,
                      child:
                          Center(child: Icon(Icons.broken_image_outlined))),
            ),
          ),
          _metaCard(context, store, p),
          ListTile(
            title: Text(tr(zh: '备注', en: 'Note')),
            subtitle: Text(p.note.isEmpty
                ? tr(zh: '点按添加备注', en: 'Tap to add a note')
                : p.note),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editNote(store, p),
          ),
        ],
      ),
    );
  }

  /// The photo's geo-evidence as one rounded card: label/value rows separated
  /// by hairline dividers, values set in tabular figures so coordinates align.
  Widget _metaCard(BuildContext context, FieldStampStore store, StampPhoto p) {
    final rows = <(String, String)>[
      (tr(zh: '项目', en: 'Project'), store.projectName(p.projectId)),
      (tr(zh: '时间', en: 'Timestamp'), formatTimestamp(p.capturedAt)),
      (
        tr(zh: '坐标', en: 'Coordinates'),
        formatLatLon(p.latitude, p.longitude, store.coordFormat,
            noFix: tr(zh: '无定位', en: 'No GPS fix'))
      ),
      (
        tr(zh: '海拔', en: 'Altitude'),
        formatAltitude(p.altitude, store.altUnit)
      ),
      (tr(zh: '方位', en: 'Bearing'), formatHeading(p.heading)),
      (
        tr(zh: 'GPS 精度', en: 'GPS accuracy'),
        p.accuracy != null ? '±${p.accuracy!.toStringAsFixed(0)} m' : '—'
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _metaRow(context, rows[i].$1, rows[i].$2),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metaRow(BuildContext context, String k, String v) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(k,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(v,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }

  Future<void> _editNote(FieldStampStore store, StampPhoto p) async {
    final ctrl = TextEditingController(text: p.note);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '备注', en: 'Note')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr(zh: '取消', en: 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr(zh: '保存', en: 'Save'))),
        ],
      ),
    );
    if (v != null) {
      store.updateNote(p, v.trim());
      setState(() {});
    }
  }
}
