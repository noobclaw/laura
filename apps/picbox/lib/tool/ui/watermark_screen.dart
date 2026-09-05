import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../engine/jobs.dart';
import '../engine/watermark_math.dart';
import '../models.dart';
import '../pro.dart';
import '../store.dart';
import 'tool_flow.dart';
import 'widgets.dart';

const List<(int, String)> _colorChoices = [
  (0xFFFFFFFF, 'white'),
  (0xFF000000, 'black'),
  (0xFFE53935, 'red'),
  (0xFFFDD835, 'yellow'),
  (0xFF0F8B8D, 'teal'),
];

/// Text watermark, single (9 anchors) or tiled, with a live preview that
/// uses the very same placement maths as the export.
class WatermarkScreen extends StatefulWidget {
  const WatermarkScreen({super.key, required this.store});
  final PicboxStore store;

  @override
  State<WatermarkScreen> createState() => _WatermarkScreenState();
}

class _WatermarkScreenState extends State<WatermarkScreen> {
  WatermarkSpec _spec = const WatermarkSpec();
  late final TextEditingController _text;
  int _quality = 92;

  static const _key = 'watermark';

  @override
  void initState() {
    super.initState();
    final s = widget.store.settingsFor(_key);
    if (s != null) {
      _spec = WatermarkSpec.fromJson(Map<String, dynamic>.from(s['spec'] as Map? ?? const {}));
      _quality = (s['quality'] as num?)?.toInt() ?? 92;
    }
    _text = TextEditingController(text: _spec.text);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _remember() => widget.store.rememberSettings(_key, {'spec': _spec.toJson(), 'quality': _quality});

  void _set(WatermarkSpec s) => setState(() => _spec = s);

  Future<void> _savePreset() async {
    if (!widget.store.pro) {
      await showProSheet(context, reason: tr(zh: '保存水印预设是 Pro 功能。', en: 'Watermark presets are a Pro feature.'));
      return;
    }
    final ctrl = TextEditingController(text: _spec.text.length > 12 ? _spec.text.substring(0, 12) : _spec.text);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '保存为预设', en: 'Save as preset')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 24,
          decoration: InputDecoration(labelText: tr(zh: '预设名称', en: 'Preset name')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(zh: '取消', en: 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr(zh: '保存', en: 'Save'))),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    widget.store.addPreset(WatermarkPreset(name: name, spec: _spec));
    setState(() {});
    showNotice(context, tr(zh: '已保存预设「$name」', en: 'Preset "$name" saved'));
  }

  Future<JobResult> _runOne(SourceImage src, RunContext ctx) async {
    final fmt = src.format == ImageFormat.heic || !src.format.writable ? ImageFormat.jpeg : src.format;
    final path = ctx.pathFor(src, fmt.extension);
    final short = math.min(src.width, src.height);
    final fontPx = watermarkFontPx(short, _spec.sizePercent);
    final margin = watermarkMarginPx(short, _spec.marginPercent);
    final sprite = await renderTextSprite(
      text: _spec.text,
      fontPx: fontPx.toDouble(),
      color: Color(_spec.colorArgb),
      shadow: _spec.shadow,
      maxWidth: math.max(fontPx.toDouble(), (src.width - margin * 2).toDouble()),
    );
    final tmp = fmt == ImageFormat.webp ? '$path.png' : path;
    final out = await runDartJob(DartJobSpec(
      inputPath: src.path,
      outputPath: tmp,
      format: fmt,
      quality: _quality,
      keepMetadata: true,
      edit: DartEdit(
        watermark: WatermarkJob(rgba: sprite.rgba, width: sprite.width, height: sprite.height, spec: _spec),
        fillWhiteIfAlpha: fmt == ImageFormat.jpeg,
      ),
    ));
    var bytes = out.bytes;
    if (fmt == ImageFormat.webp) {
      final webp = await pngToWebp(tmp, _quality);
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final presets = widget.store.presets;
    return ToolScaffold(
      kind: ToolKind.watermark,
      store: widget.store,
      runOne: _runOne,
      onBeforeRun: _remember,
      blocker: _spec.text.trim().isEmpty ? tr(zh: '请输入水印文字', en: 'Enter the watermark text') : null,
      preview: (context, images) {
        final s = images.first;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: math.max(0.6, math.min(1.8, s.width / s.height)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(s.path), fit: BoxFit.contain, cacheWidth: 1200, gaplessPlayback: true),
                  LayoutBuilder(
                    builder: (context, c) {
                      // Fit the image box inside the preview the way BoxFit.contain does.
                      final box = Size(c.maxWidth, c.maxHeight);
                      final scale = math.min(box.width / s.width, box.height / s.height);
                      final imgSize = Size(s.width * scale, s.height * scale);
                      final offset = Offset((box.width - imgSize.width) / 2, (box.height - imgSize.height) / 2);
                      return CustomPaint(
                        painter: _PreviewPainter(spec: _spec, imageSize: imgSize, offset: offset, imageShortPx: math.min(s.width, s.height)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
      options: (context, images) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: tr(zh: '文字', en: 'Text'),
            trailing: TextButton.icon(
              onPressed: _savePreset,
              icon: Icon(widget.store.pro ? Icons.bookmark_add_outlined : Icons.lock_outline, size: 18),
              label: Text(tr(zh: '存为预设', en: 'Save preset')),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _text,
                  maxLength: 60,
                  decoration: InputDecoration(
                    hintText: tr(zh: '例如 © 2026 我的名字', en: 'e.g. © 2026 My Name'),
                    counterText: '',
                  ),
                  onChanged: (v) => _set(_spec.copyWith(text: v)),
                ),
                if (presets.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in presets)
                        InputChip(
                          avatar: const Icon(Icons.bookmark_outline, size: 16),
                          label: Text(p.name),
                          onPressed: () {
                            _text.text = p.spec.text;
                            _set(p.spec);
                          },
                          onDeleted: () {
                            widget.store.removePreset(p.name);
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ] else if (!widget.store.pro)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(tr(zh: 'Pro 可保存常用水印,一键套用', en: 'Pro saves your usual marks for one-tap reuse'),
                        style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: tr(zh: '位置', en: 'Placement'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(tr(zh: '单个', en: 'Single')), icon: const Icon(Icons.crop_free_rounded)),
                    ButtonSegment(value: true, label: Text(tr(zh: '平铺', en: 'Tiled')), icon: const Icon(Icons.grid_on_rounded)),
                  ],
                  selected: {_spec.tiled},
                  onSelectionChanged: (s) => _set(_spec.copyWith(tiled: s.first)),
                ),
                const SizedBox(height: 14),
                if (!_spec.tiled)
                  Center(child: _AnchorGrid(value: _spec.anchor, onChanged: (a) => _set(_spec.copyWith(anchor: a))))
                else
                  LabeledSlider(
                    label: tr(zh: '倾斜角度', en: 'Angle'),
                    value: _spec.tileAngleDeg.toDouble(),
                    min: -90,
                    max: 90,
                    divisions: 36,
                    display: '${_spec.tileAngleDeg}°',
                    onChanged: (v) => _set(_spec.copyWith(tileAngleDeg: (v / 5).round() * 5)),
                  ),
                if (!_spec.tiled)
                  LabeledSlider(
                    label: tr(zh: '边距', en: 'Margin'),
                    value: _spec.marginPercent.toDouble(),
                    min: 0,
                    max: 20,
                    divisions: 20,
                    display: '${_spec.marginPercent}%',
                    onChanged: (v) => _set(_spec.copyWith(marginPercent: v.round())),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: tr(zh: '样式', en: 'Style'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledSlider(
                  label: tr(zh: '大小', en: 'Size'),
                  value: _spec.sizePercent.toDouble(),
                  min: 1,
                  max: 20,
                  divisions: 19,
                  display: '${_spec.sizePercent}%',
                  onChanged: (v) => _set(_spec.copyWith(sizePercent: v.round())),
                ),
                LabeledSlider(
                  label: tr(zh: '不透明度', en: 'Opacity'),
                  value: _spec.opacity,
                  min: 0.05,
                  max: 1,
                  divisions: 19,
                  display: '${(_spec.opacity * 100).round()}%',
                  onChanged: (v) => _set(_spec.copyWith(opacity: (v * 20).round() / 20)),
                ),
                Row(
                  children: [
                    Text(tr(zh: '颜色', en: 'Colour'), style: text.bodyMedium),
                    const SizedBox(width: 12),
                    for (final (argb, _) in _colorChoices)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () => _set(_spec.copyWith(colorArgb: argb)),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Color(argb),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _spec.colorArgb == argb ? cs.primary : cs.outlineVariant,
                                width: _spec.colorArgb == argb ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SwitchRow(
                  label: tr(zh: '文字投影', en: 'Text shadow'),
                  subtitle: tr(zh: '浅色背景上更清楚', en: 'Keeps light text readable on light areas'),
                  value: _spec.shadow,
                  onChanged: (v) => _set(_spec.copyWith(shadow: v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnchorGrid extends StatelessWidget {
  const _AnchorGrid({required this.value, required this.onChanged});
  final WatermarkAnchor value;
  final ValueChanged<WatermarkAnchor> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < 3; r++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var c = 0; c < 3; c++)
                  Builder(builder: (context) {
                    final a = WatermarkAnchor.values[r * 3 + c];
                    final sel = a == value;
                    return GestureDetector(
                      onTap: () => onChanged(a),
                      child: Container(
                        width: 44,
                        height: 34,
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: sel ? cs.primary : cs.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.text_fields_rounded, size: 16, color: sel ? cs.onPrimary : cs.onSurfaceVariant),
                      ),
                    );
                  }),
              ],
            ),
        ],
      ),
    );
  }
}

/// Draws the watermark over the preview using the export maths scaled to
/// the on-screen image size.
class _PreviewPainter extends CustomPainter {
  _PreviewPainter({required this.spec, required this.imageSize, required this.offset, required this.imageShortPx});
  final WatermarkSpec spec;
  final Size imageSize;
  final Offset offset;
  final int imageShortPx;

  @override
  void paint(Canvas canvas, Size size) {
    if (spec.text.trim().isEmpty || imageSize.isEmpty) return;
    final scale = math.min(imageSize.width, imageSize.height) / imageShortPx;
    final fontPx = watermarkFontPx(imageShortPx, spec.sizePercent) * scale;
    final margin = watermarkMarginPx(imageShortPx, spec.marginPercent) * scale;
    final tp = buildWatermarkPainter(
      text: spec.text,
      fontPx: fontPx,
      color: Color(spec.colorArgb).withValues(alpha: spec.opacity),
      shadow: spec.shadow,
      maxWidth: math.max(fontPx, imageSize.width - margin * 2),
    );
    final sw = tp.width.ceil();
    final sh = tp.height.ceil();
    canvas.save();
    canvas.clipRect(offset & imageSize);
    canvas.translate(offset.dx, offset.dy);
    final w = imageSize.width.round();
    final h = imageSize.height.round();
    if (spec.tiled) {
      final rb = rotatedBounds(sw, sh, spec.tileAngleDeg);
      for (final p in tilePositions(w: w, h: h, spriteW: rb.width, spriteH: rb.height)) {
        canvas.save();
        canvas.translate(p.x + rb.width / 2, p.y + rb.height / 2);
        canvas.rotate(spec.tileAngleDeg * math.pi / 180);
        tp.paint(canvas, Offset(-sw / 2, -sh / 2));
        canvas.restore();
      }
    } else {
      final o = anchorOffset(w: w, h: h, spriteW: sw, spriteH: sh, margin: margin.round(), anchor: spec.anchor);
      tp.paint(canvas, Offset(o.x.toDouble(), o.y.toDouble()));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.spec != spec || old.imageSize != imageSize || old.offset != offset || old.imageShortPx != imageShortPx;
}

/// Lay out the watermark text; shared by preview and export so both agree.
TextPainter buildWatermarkPainter({
  required String text,
  required double fontPx,
  required Color color,
  required bool shadow,
  required double maxWidth,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontPx,
        fontWeight: FontWeight.w600,
        height: 1.2,
        shadows: shadow
            ? [Shadow(color: Colors.black.withValues(alpha: 0.55 * color.a), blurRadius: fontPx * 0.12, offset: Offset(fontPx * 0.03, fontPx * 0.04))]
            : null,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 3,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  return tp;
}

/// Render the text to an RGBA sprite at export resolution (UI isolate only).
/// Opacity is applied later on the sprite's alpha, so the colour here is
/// fully opaque and the shadow scales with it.
Future<({Uint8List rgba, int width, int height})> renderTextSprite({
  required String text,
  required double fontPx,
  required Color color,
  required bool shadow,
  required double maxWidth,
}) async {
  final tp = buildWatermarkPainter(text: text, fontPx: fontPx, color: color.withValues(alpha: 1), shadow: shadow, maxWidth: maxWidth);
  final pad = (fontPx * 0.25).ceil(); // room for the shadow blur
  final w = math.max(1, tp.width.ceil() + pad * 2);
  final h = math.max(1, tp.height.ceil() + pad * 2);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  tp.paint(canvas, Offset(pad.toDouble(), pad.toDouble()));
  final pic = rec.endRecording();
  final image = await pic.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  image.dispose();
  pic.dispose();
  if (data == null) throw JobError(JobFailure.encode);
  return (rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), width: w, height: h);
}
