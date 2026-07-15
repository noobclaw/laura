import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'export.dart';
import 'geo_format.dart';
import 'models.dart';
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
              child: photos.isEmpty
                  ? const _EmptyGallery()
                  : _grid(store, photos),
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
                child: Text('${_selected.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Share images',
                icon: const Icon(Icons.ios_share),
                onPressed:
                    _selected.isEmpty || _busy ? null : () => _shareImages(store),
              ),
              IconButton(
                tooltip: 'PDF report',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed:
                    _selected.isEmpty || _busy ? null : () => _exportPdf(store),
              ),
              IconButton(
                tooltip: 'CSV ledger',
                icon: const Icon(Icons.table_chart_outlined),
                onPressed:
                    _selected.isEmpty || _busy ? null : () => _exportCsv(store),
              ),
              IconButton(
                tooltip: 'Delete',
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
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${store.projectName(store.currentProjectId)} · ${photos.length} photos',
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (photos.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.checklist, size: 18),
                label: const Text('Select'),
                onPressed: () => setState(() => _selecting = true),
              ),
          ],
        ),
      ),
    );
  }

  Widget _grid(FieldStampStore store, List<StampPhoto> photos) {
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: photos.length,
      itemBuilder: (context, i) {
        final p = photos[i];
        final selected = _selected.contains(p.id);
        return GestureDetector(
          onTap: () {
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
                builder: (_) => PhotoDetailScreen(store: store, photo: p),
              ));
            }
          },
          onLongPress: () => setState(() {
            _selecting = true;
            _selected.add(p.id);
          }),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _thumb(store, p),
              if (!p.hasFix)
                const Positioned(
                  left: 4,
                  top: 4,
                  child: Icon(Icons.gps_off,
                      size: 16, color: Colors.orangeAccent),
                ),
              if (_selecting)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? Colors.lightGreenAccent : Colors.white70,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _thumb(FieldStampStore store, StampPhoto p) {
    final file = File(store.photoPath(p.fileName));
    return Container(
      color: Colors.black12,
      child: file.existsSync()
          ? Image.file(file, fit: BoxFit.cover,
              cacheWidth: 300, gaplessPlayback: true, errorBuilder: (_, _, _) {
              return const Icon(Icons.broken_image_outlined);
            })
          : const Icon(Icons.broken_image_outlined),
    );
  }

  List<StampPhoto> _selectedPhotos(FieldStampStore store) {
    final all = store.photosForProject(store.currentProjectId);
    return all.where((p) => _selected.contains(p.id)).toList();
  }

  bool _enforceLimit(FieldStampStore store, int count) {
    if (store.pro || count <= FieldStampStore.freeExportLimit) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Free reports are limited to ${FieldStampStore.freeExportLimit} photos. '
          'Unlock Pro in Settings for unlimited exports.'),
    ));
    return false;
  }

  Future<void> _shareImages(FieldStampStore store) async {
    final photos = _selectedPhotos(store);
    if (photos.isEmpty) return;
    setState(() => _busy = true);
    try {
      await sharePhotos(photos, store);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPdf(FieldStampStore store) async {
    final photos = _selectedPhotos(store);
    if (photos.isEmpty) return;
    if (!store.pro) {
      _proNeeded('PDF report');
      return;
    }
    if (!_enforceLimit(store, photos.length)) return;
    setState(() => _busy = true);
    try {
      final bytes = await buildPdf(photos, store);
      final name = _fileStamp('fieldstamp-report', 'pdf');
      await shareBytes(bytes, name, text: 'FieldStamp inspection report');
    } catch (e) {
      _snack('PDF export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv(FieldStampStore store) async {
    final photos = _selectedPhotos(store);
    if (photos.isEmpty) return;
    if (!store.pro) {
      _proNeeded('CSV export');
      return;
    }
    if (!_enforceLimit(store, photos.length)) return;
    setState(() => _busy = true);
    try {
      final csv = buildCsv(photos, store);
      final name = _fileStamp('fieldstamp-ledger', 'csv');
      await shareBytes(utf8.encode(csv), name, text: 'FieldStamp CSV ledger');
    } catch (e) {
      _snack('CSV export failed: $e');
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
        title: Text('Delete ${photos.length} photos?'),
        content: const Text('This permanently removes them from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$feature is a Pro feature. Unlock it in Settings.'),
    ));
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

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('No photos yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Switch to the Camera tab and tap the shutter.\n'
              'Each photo is stamped with GPS, time and bearing.',
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
  const PhotoDetailScreen({super.key, required this.store, required this.photo});

  final FieldStampStore store;
  final StampPhoto photo;

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
        title: const Text('Photo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: () => sharePhotos([p], store),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete photo?'),
                  content: const Text('This cannot be undone.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
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
            child: file.existsSync()
                ? Image.file(file, fit: BoxFit.contain)
                : const SizedBox(
                    height: 240,
                    child: Center(child: Icon(Icons.broken_image_outlined))),
          ),
          _meta('Project', store.projectName(p.projectId)),
          _meta('Timestamp', formatTimestamp(p.capturedAt)),
          _meta('Coordinates',
              formatLatLon(p.latitude, p.longitude, store.coordFormat)),
          _meta('Altitude', formatAltitude(p.altitude, store.altUnit)),
          _meta('Bearing', formatHeading(p.heading)),
          _meta('GPS accuracy',
              p.accuracy != null ? '±${p.accuracy!.toStringAsFixed(0)} m' : '—'),
          ListTile(
            title: const Text('Note'),
            subtitle: Text(p.note.isEmpty ? 'Tap to add a note' : p.note),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editNote(store, p),
          ),
        ],
      ),
    );
  }

  Widget _meta(String k, String v) => ListTile(
        dense: true,
        title: Text(k, style: const TextStyle(fontSize: 13)),
        subtitle: Text(v,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w500)),
      );

  Future<void> _editNote(FieldStampStore store, StampPhoto p) async {
    final ctrl = TextEditingController(text: p.note);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (v != null) {
      store.updateNote(p, v.trim());
      setState(() {});
    }
  }
}
