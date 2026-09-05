import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../engine/jobs.dart';
import '../models.dart';
import '../store.dart';
import 'tool_flow.dart';
import 'widgets.dart';

/// Aspect presets (subset of the reference app's 26, the ones people use).
/// `null` ratio = free; `0` = original.
const List<(String, double?)> _presets = [
  ('Free', null),
  ('Orig', 0),
  ('1:1', 1),
  ('4:3', 4 / 3),
  ('3:4', 3 / 4),
  ('16:9', 16 / 9),
  ('9:16', 9 / 16),
  ('3:2', 3 / 2),
  ('2:3', 2 / 3),
  ('4:5', 4 / 5),
  ('5:4', 5 / 4),
  ('2:1', 2),
  ('21:9', 21 / 9),
];

/// Per-image edit, in the *displayed* (rotated/flipped) space, normalised.
class _Edit {
  _Edit();
  Rect rect = const Rect.fromLTWH(0, 0, 1, 1);
  int presetIndex = 0;
  int rotate = 0; // clockwise degrees
  bool flipH = false;
  bool flipV = false;

  bool get isIdentity => rect == const Rect.fromLTWH(0, 0, 1, 1) && rotate == 0 && !flipH && !flipV;

  _Edit copy() => _Edit()
    ..rect = rect
    ..presetIndex = presetIndex
    ..rotate = rotate
    ..flipH = flipH
    ..flipV = flipV;
}

/// Crop with ratio presets, 90° rotation and flips. Each image keeps its
/// own edit; "Apply to all" copies the current one across the batch.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.store});
  final PicboxStore store;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final Map<String, _Edit> _edits = {};
  String? _currentId;
  List<SourceImage> _images = const [];

  _Edit _editFor(SourceImage s) => _edits.putIfAbsent(s.id, _Edit.new);

  SourceImage? get _current {
    if (_images.isEmpty) return null;
    return _images.firstWhere((s) => s.id == _currentId, orElse: () => _images.first);
  }

  void _onImages(List<SourceImage> images) {
    setState(() {
      _images = images;
      _edits.removeWhere((id, _) => !images.any((s) => s.id == id));
      if (_current == null || !images.any((s) => s.id == _currentId)) {
        _currentId = images.isEmpty ? null : images.first.id;
      }
    });
  }

  /// Displayed size of [s] under [e] (rotation swaps the sides).
  (int, int) _displayed(SourceImage s, _Edit e) =>
      e.rotate % 180 == 0 ? (s.width, s.height) : (s.height, s.width);

  /// Largest centred rect of aspect [ratio] (w/h) inside a dw×dh image.
  Rect _fitRect(double ratio, int dw, int dh) {
    final imgRatio = dw / dh;
    double w;
    double h;
    if (ratio >= imgRatio) {
      w = 1;
      h = imgRatio / ratio;
    } else {
      h = 1;
      w = ratio / imgRatio;
    }
    return Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
  }

  void _applyPreset(SourceImage s, _Edit e, int index) {
    e.presetIndex = index;
    final ratio = _presets[index].$2;
    final (dw, dh) = _displayed(s, e);
    if (ratio == null) {
      e.rect = const Rect.fromLTWH(0, 0, 1, 1);
    } else if (ratio == 0) {
      e.rect = const Rect.fromLTWH(0, 0, 1, 1);
    } else {
      e.rect = _fitRect(ratio, dw, dh);
    }
  }

  double? _lockedRatio(SourceImage s, _Edit e) {
    final r = _presets[e.presetIndex].$2;
    if (r == null) return null;
    final (dw, dh) = _displayed(s, e);
    return r == 0 ? dw / dh : r;
  }

  void _rotate(SourceImage s, _Edit e, int delta) {
    e.rotate = (e.rotate + delta + 360) % 360;
    // The crop box keeps its preset but is re-fitted to the new orientation.
    _applyPreset(s, e, e.presetIndex);
  }

  void _applyToAll(SourceImage from) {
    final src = _editFor(from);
    for (final s in _images) {
      if (s.id == from.id) continue;
      final e = src.copy();
      _edits[s.id] = e;
      final ratio = _presets[e.presetIndex].$2;
      if (ratio != null) _applyPreset(s, e, e.presetIndex);
    }
    showNotice(context, tr(zh: '已应用到全部 ${_images.length} 张', en: 'Applied to all ${_images.length}'));
  }

  Future<JobResult> _runOne(SourceImage src, RunContext ctx) async {
    final e = _edits[src.id] ?? _Edit();
    final fmt = src.format == ImageFormat.heic || !src.format.writable ? ImageFormat.jpeg : src.format;
    final path = ctx.pathFor(src, fmt.extension);
    final (dw, dh) = _displayed(src, e);
    final r = e.rect;
    final x = (r.left * dw).round();
    final y = (r.top * dh).round();
    final w = math.max(1, (r.width * dw).round());
    final h = math.max(1, (r.height * dh).round());
    final tmp = fmt == ImageFormat.webp ? '$path.png' : path;
    final out = await runDartJob(DartJobSpec(
      inputPath: src.path,
      outputPath: tmp,
      format: fmt,
      quality: 92,
      keepMetadata: true,
      edit: DartEdit(
        rotate: e.rotate,
        flipH: e.flipH,
        flipV: e.flipV,
        cropX: x,
        cropY: y,
        cropW: w,
        cropH: h,
      ),
    ));
    var bytes = out.bytes;
    if (fmt == ImageFormat.webp) {
      final webp = await pngToWebp(tmp, 92);
      await File(path).writeAsBytes(webp, flush: true);
      bytes = webp.length;
      try {
        await File(tmp).delete();
      } catch (_) {}
    }
    return JobResult(
      source: src,
      outputPath: path,
      outputBytes: bytes,
      outputWidth: out.width,
      outputHeight: out.height,
      outputFormat: fmt,
      note: e.isIdentity ? tr(zh: '未做修改,已重新编码', en: 'No edits; re-encoded') : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ToolScaffold(
      kind: ToolKind.crop,
      store: widget.store,
      runOne: _runOne,
      onImagesChanged: _onImages,
      preview: (context, images) {
        final s = _current;
        if (s == null) return const SizedBox.shrink();
        final e = _editFor(s);
        final (dw, dh) = _displayed(s, e);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (images.length > 1)
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final img = images[i];
                    final sel = img.id == s.id;
                    return GestureDetector(
                      onTap: () => setState(() => _currentId = img.id),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: sel ? cs.primary : Colors.transparent, width: 2),
                        ),
                        child: ImageThumb(path: img.path, size: 36, radius: 8),
                      ),
                    );
                  },
                ),
              ),
            if (images.length > 1) const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: Colors.black,
                child: AspectRatio(
                  aspectRatio: math.max(0.5, math.min(2.0, dw / dh)),
                  child: _CropEditor(
                    key: ValueKey('${s.id}-${e.rotate}-${e.flipH}-${e.flipV}'),
                    image: s,
                    edit: e,
                    lockedRatio: _lockedRatio(s, e),
                    onChanged: (r) => setState(() => e.rect = r),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${(e.rect.width * dw).round()}×${(e.rect.height * dh).round()} px'
                    '${images.length > 1 ? tr(zh: ' · 第 ${images.indexOf(s) + 1}/${images.length} 张', en: ' · ${images.indexOf(s) + 1} of ${images.length}') : ''}',
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                if (images.length > 1)
                  TextButton.icon(
                    onPressed: () => _applyToAll(s),
                    icon: const Icon(Icons.copy_all_rounded, size: 18),
                    label: Text(tr(zh: '应用到全部', en: 'Apply to all')),
                  ),
              ],
            ),
          ],
        );
      },
      options: (context, images) {
        final s = _current;
        if (s == null) {
          return SectionCard(
            title: tr(zh: '这个工具做什么', en: 'What this does'),
            child: Text(
              tr(
                zh: '拖动裁剪框或选一个比例预设,按 90° 旋转、水平/垂直翻转。手机拍的竖图会先按拍摄方向摆正再裁,不会歪。',
                en: 'Drag the crop box or pick a ratio preset; rotate in 90° steps and flip. Phone photos are put upright from their EXIF orientation before cropping.',
              ),
              style: text.bodyMedium?.copyWith(height: 1.45),
            ),
          );
        }
        final e = _editFor(s);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: tr(zh: '比例', en: 'Aspect ratio'),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, p) in _presets.indexed)
                    ChoiceChip(
                      label: Text(i == 0
                          ? tr(zh: '自由', en: 'Free')
                          : i == 1
                              ? tr(zh: '原图', en: 'Original')
                              : p.$1),
                      selected: e.presetIndex == i,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _applyPreset(s, e, i)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: tr(zh: '旋转与翻转', en: 'Rotate & flip'),
              child: Row(
                children: [
                  _IconAction(icon: Icons.rotate_left_rounded, label: '−90°', onTap: () => setState(() => _rotate(s, e, -90))),
                  _IconAction(icon: Icons.rotate_right_rounded, label: '+90°', onTap: () => setState(() => _rotate(s, e, 90))),
                  _IconAction(
                    icon: Icons.flip_rounded,
                    label: tr(zh: '水平', en: 'Horiz.'),
                    active: e.flipH,
                    onTap: () => setState(() => e.flipH = !e.flipH),
                  ),
                  _IconAction(
                    icon: Icons.flip_rounded,
                    label: tr(zh: '垂直', en: 'Vert.'),
                    active: e.flipV,
                    rotateIcon: true,
                    onTap: () => setState(() => e.flipV = !e.flipV),
                  ),
                  _IconAction(
                    icon: Icons.restart_alt_rounded,
                    label: tr(zh: '重置', en: 'Reset'),
                    onTap: () => setState(() => _edits[s.id] = _Edit()),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.label, required this.onTap, this.active = false, this.rotateIcon = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool rotateIcon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: active ? cs.primaryContainer : Colors.transparent,
          ),
          child: Column(
            children: [
              RotatedBox(quarterTurns: rotateIcon ? 1 : 0, child: Icon(icon, color: active ? cs.onPrimaryContainer : cs.onSurface)),
              const SizedBox(height: 4),
              Text(label, style: text.labelSmall?.copyWith(color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The image with rotation/flip applied and a draggable crop rectangle on
/// top. Rect is normalised to the displayed image bounds.
class _CropEditor extends StatefulWidget {
  const _CropEditor({super.key, required this.image, required this.edit, required this.lockedRatio, required this.onChanged});
  final SourceImage image;
  final _Edit edit;
  final double? lockedRatio;
  final ValueChanged<Rect> onChanged;

  @override
  State<_CropEditor> createState() => _CropEditorState();
}

enum _Handle { move, tl, tr, bl, br }

class _CropEditorState extends State<_CropEditor> {
  _Handle? _active;
  Rect _start = Rect.zero;
  Offset _startPos = Offset.zero;

  static const double _minSize = 0.05;

  _Handle _hit(Offset p, Rect r, Size size) {
    final px = Rect.fromLTWH(r.left * size.width, r.top * size.height, r.width * size.width, r.height * size.height);
    const grab = 28.0;
    bool near(Offset c) => (p - c).distance <= grab;
    if (near(px.topLeft)) return _Handle.tl;
    if (near(px.topRight)) return _Handle.tr;
    if (near(px.bottomLeft)) return _Handle.bl;
    if (near(px.bottomRight)) return _Handle.br;
    return _Handle.move;
  }

  void _drag(Offset delta, Size size) {
    final dx = delta.dx / size.width;
    final dy = delta.dy / size.height;
    var r = widget.edit.rect;
    final s = _start;
    final ratio = widget.lockedRatio; // in displayed-pixel terms (w/h)
    // Aspect of the display box, to convert a pixel ratio into normalised
    // units: normalised w/h = pixel ratio / box ratio.
    final boxRatio = size.width / size.height;
    switch (_active) {
      case _Handle.move:
        r = Rect.fromLTWH(
          (s.left + dx).clamp(0, 1 - s.width),
          (s.top + dy).clamp(0, 1 - s.height),
          s.width,
          s.height,
        );
      case _Handle.br:
      case _Handle.tr:
      case _Handle.bl:
      case _Handle.tl:
        final anchorX = _active == _Handle.br || _active == _Handle.tr ? s.left : s.right;
        final anchorY = _active == _Handle.br || _active == _Handle.bl ? s.top : s.bottom;
        final movingX = (_active == _Handle.br || _active == _Handle.tr ? s.right : s.left) + dx;
        final movingY = (_active == _Handle.br || _active == _Handle.bl ? s.bottom : s.top) + dy;
        var w = (movingX - anchorX).abs();
        var h = (movingY - anchorY).abs();
        if (ratio != null) {
          final nr = ratio / boxRatio;
          // Follow the dominant drag direction, derive the other side.
          if (w / nr >= h) {
            h = w / nr;
          } else {
            w = h * nr;
          }
        }
        w = math.max(w, _minSize);
        h = math.max(h, ratio != null ? _minSize / (ratio / boxRatio) : _minSize);
        // Clamp so the moving corner stays inside the canvas.
        final signX = movingX >= anchorX ? 1 : -1;
        final signY = movingY >= anchorY ? 1 : -1;
        final maxW = signX > 0 ? 1 - anchorX : anchorX;
        final maxH = signY > 0 ? 1 - anchorY : anchorY;
        if (ratio != null) {
          final nr = ratio / boxRatio;
          if (w > maxW) {
            w = maxW;
            h = w / nr;
          }
          if (h > maxH) {
            h = maxH;
            w = h * nr;
          }
        } else {
          w = math.min(w, maxW);
          h = math.min(h, maxH);
        }
        final left = signX > 0 ? anchorX : anchorX - w;
        final top = signY > 0 ? anchorY : anchorY - h;
        r = Rect.fromLTWH(left, top, w, h);
      case null:
        return;
    }
    widget.onChanged(r);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.edit;
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        // An eager pan recognizer: it claims the pointer on touch-down so the
        // surrounding ListView cannot turn a vertical drag of the crop box
        // into a scroll (a plain onPan loses that arena to the scrollable).
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            _EagerPanRecognizer: GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
              _EagerPanRecognizer.new,
              (r) {
                r.onStart = (d) {
                  _active = _hit(d.localPosition, e.rect, size);
                  _start = e.rect;
                  _startPos = d.localPosition;
                };
                r.onUpdate = (d) => _drag(d.localPosition - _startPos, size);
                r.onEnd = (_) {
                  _active = null;
                };
                r.onCancel = () {
                  _active = null;
                };
              },
            ),
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform.flip(
                flipX: e.flipH,
                flipY: e.flipV,
                child: RotatedBox(
                  quarterTurns: e.rotate ~/ 90,
                  child: Image.file(
                    File(widget.image.path),
                    fit: BoxFit.fill,
                    cacheWidth: 1200,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              CustomPaint(painter: _CropPainter(e.rect, Theme.of(context).colorScheme.primary)),
            ],
          ),
        );
      },
    );
  }
}

/// Pan recognizer that wins the gesture arena on pointer-down.
class _EagerPanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.rect, this.accent);
  final Rect rect;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final px = Rect.fromLTWH(rect.left * size.width, rect.top * size.height, rect.width * size.width, rect.height * size.height);
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRect(px)),
      dim,
    );
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(px, line);
    final thin = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(px.left + px.width * i / 3, px.top), Offset(px.left + px.width * i / 3, px.bottom), thin);
      canvas.drawLine(Offset(px.left, px.top + px.height * i / 3), Offset(px.right, px.top + px.height * i / 3), thin);
    }
    final handle = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 18.0;
    void corner(Offset o, double sx, double sy) {
      canvas.drawLine(o, o + Offset(l * sx, 0), handle);
      canvas.drawLine(o, o + Offset(0, l * sy), handle);
    }

    corner(px.topLeft, 1, 1);
    corner(px.topRight, -1, 1);
    corner(px.bottomLeft, 1, -1);
    corner(px.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect || old.accent != accent;
}
