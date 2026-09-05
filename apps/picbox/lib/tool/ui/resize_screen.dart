import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../engine/jobs.dart';
import '../engine/resize_math.dart';
import '../models.dart';
import '../pro.dart';
import '../store.dart';
import 'tool_flow.dart';
import 'widgets.dart';

/// Resize by pixels / percent / longest side. Shrinking with the aspect kept
/// goes through the native codec; stretching or upscaling through Dart.
class ResizeScreen extends StatefulWidget {
  const ResizeScreen({super.key, required this.store});
  final PicboxStore store;

  @override
  State<ResizeScreen> createState() => _ResizeScreenState();
}

class _ResizeScreenState extends State<ResizeScreen> {
  ResizeMode _mode = ResizeMode.longestSide;
  int? _w = 1080;
  int? _h;
  int _percent = 50;
  int _longest = 1920;
  bool _keepAspect = true;
  bool _upscale = false;
  ImageFormat? _format;
  int _quality = 90;
  bool _keepExif = true;

  static const _key = 'resize';

  @override
  void initState() {
    super.initState();
    final s = widget.store.settingsFor(_key);
    if (s != null) {
      final spec = ResizeSpec.fromJson(Map<String, dynamic>.from(s['spec'] as Map? ?? const {}));
      _mode = spec.mode;
      _w = spec.width;
      _h = spec.height;
      _percent = spec.percent;
      _longest = spec.longest;
      _keepAspect = spec.keepAspect;
      _upscale = spec.allowUpscale;
      final f = s['format'] as String?;
      _format = f == null ? null : ImageFormatX.fromName(f);
      _quality = (s['quality'] as num?)?.toInt() ?? 90;
      _keepExif = s['keepExif'] as bool? ?? true;
    }
  }

  ResizeSpec get _spec => ResizeSpec(
        mode: _mode,
        width: _w,
        height: _h,
        percent: _percent,
        longest: _longest,
        keepAspect: _keepAspect,
        allowUpscale: _upscale,
      );

  void _remember() => widget.store.rememberSettings(_key, {
        'spec': _spec.toJson(),
        'format': _format?.name,
        'quality': _quality,
        'keepExif': _keepExif,
      });

  String? get _blocker {
    if (_mode == ResizeMode.pixels && _w == null && _h == null) {
      return tr(zh: '请至少填写宽或高', en: 'Enter a width or a height');
    }
    if (_mode == ResizeMode.pixels && !_keepAspect && (_w == null || _h == null)) {
      return tr(zh: '不保持比例时需要同时填写宽和高', en: 'Stretching needs both width and height');
    }
    return null;
  }

  ImageFormat _outFormat(SourceImage s) {
    final f = _format ?? (s.format == ImageFormat.heic ? ImageFormat.jpeg : s.format);
    return f.writable ? f : ImageFormat.jpeg;
  }

  Future<JobResult> _runOne(SourceImage src, RunContext ctx) async {
    final fmt = _outFormat(src);
    final spec = _spec;
    final target = computeResize(src.width, src.height, spec);
    final path = ctx.pathFor(src, fmt.extension);
    final upscaling = target.width > src.width || target.height > src.height;
    final stretching = !spec.keepAspect && spec.mode == ResizeMode.pixels;
    if (!upscaling && !stretching) {
      // Fast native path: fit inside the target box (never upscales).
      final input = await ensureOpaqueSource(src, fmt, ctx.outDir);
      final bytes = await nativeEncode(input,
          format: fmt,
          quality: _quality,
          keepExif: _keepExif,
          fitW: target.width,
          fitH: target.height,
          orientation: input == src.path ? src.orientation : 1);
      await File(path).writeAsBytes(bytes, flush: true);
      final p = await probeFile(path);
      return JobResult(
        source: src,
        outputPath: path,
        outputBytes: p.bytes,
        outputWidth: p.info.width,
        outputHeight: p.info.height,
        outputFormat: fmt,
      );
    }
    final tmp = fmt == ImageFormat.webp ? '$path.png' : path;
    final out = await runDartJob(DartJobSpec(
      inputPath: src.path,
      outputPath: tmp,
      format: fmt,
      quality: _quality,
      keepMetadata: _keepExif,
      edit: DartEdit(resize: spec, fillWhiteIfAlpha: fmt == ImageFormat.jpeg),
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
    return ToolScaffold(
      kind: ToolKind.resize,
      store: widget.store,
      runOne: _runOne,
      onBeforeRun: _remember,
      blocker: _blocker,
      options: (context, images) {
        final first = images.isEmpty ? null : images.first;
        final preview = first == null ? null : computeResize(first.width, first.height, _spec);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: tr(zh: '目标尺寸', en: 'Target size'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<ResizeMode>(
                    segments: [
                      ButtonSegment(value: ResizeMode.longestSide, label: Text(tr(zh: '最长边', en: 'Longest'))),
                      ButtonSegment(value: ResizeMode.percent, label: Text(tr(zh: '百分比', en: 'Percent'))),
                      ButtonSegment(value: ResizeMode.pixels, label: Text(tr(zh: '像素', en: 'Pixels'))),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 14),
                  switch (_mode) {
                    ResizeMode.longestSide => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          IntField(
                            label: tr(zh: '最长边不超过', en: 'Longest side at most'),
                            value: _longest,
                            suffix: 'px',
                            min: 16,
                            max: 16384,
                            onChanged: (v) => setState(() => _longest = v ?? 1920),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final v in const [1080, 1440, 1920, 2560, 4096])
                                ActionChip(label: Text('$v'), onPressed: () => setState(() => _longest = v)),
                            ],
                          ),
                        ],
                      ),
                    ResizeMode.percent => LabeledSlider(
                        label: tr(zh: '缩放到', en: 'Scale to'),
                        value: _percent.toDouble(),
                        min: 5,
                        max: _upscale ? 400 : 100,
                        divisions: _upscale ? 79 : 19,
                        display: '$_percent%',
                        onChanged: (v) => setState(() => _percent = (v / 5).round() * 5),
                      ),
                    ResizeMode.pixels => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: IntField(
                                  label: tr(zh: '宽', en: 'Width'),
                                  value: _w,
                                  suffix: 'px',
                                  max: 16384,
                                  onChanged: (v) => setState(() => _w = v),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(_keepAspect ? Icons.link_rounded : Icons.link_off_rounded, color: cs.onSurfaceVariant),
                              ),
                              Expanded(
                                child: IntField(
                                  label: tr(zh: '高', en: 'Height'),
                                  value: _h,
                                  suffix: 'px',
                                  max: 16384,
                                  onChanged: (v) => setState(() => _h = v),
                                ),
                              ),
                            ],
                          ),
                          SwitchRow(
                            label: tr(zh: '保持宽高比', en: 'Keep aspect ratio'),
                            subtitle: tr(zh: '只填一边即可;都填则按框内适配', en: 'Fill one side; both = fit inside the box'),
                            value: _keepAspect,
                            onChanged: (v) => setState(() => _keepAspect = v),
                          ),
                        ],
                      ),
                  },
                  SwitchRow(
                    label: tr(zh: '允许放大', en: 'Allow upscaling'),
                    subtitle: tr(zh: '默认不把小图拉大', en: 'Small pictures are never enlarged by default'),
                    value: _upscale,
                    onChanged: (v) => setState(() {
                      _upscale = v;
                      if (!v && _percent > 100) _percent = 100;
                    }),
                  ),
                  if (first != null && preview != null)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.preview_outlined, size: 18, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${first.width}×${first.height} → ${preview.width}×${preview.height}'
                              '${images.length > 1 ? tr(zh: '(第 1 张)', en: ' (first image)') : ''}',
                              style: text.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: tr(zh: '输出', en: 'Output'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormatChoice(
                    value: _format,
                    allowSame: true,
                    pro: widget.store.pro,
                    onChanged: (f) => setState(() => _format = f),
                    onProNeeded: () => showProSheet(context,
                        reason: tr(zh: 'WebP 导出是 Pro 功能。', en: 'WebP export is a Pro feature.')),
                  ),
                  const SizedBox(height: 8),
                  QualitySlider(
                    value: _quality,
                    enabled: _format != ImageFormat.png,
                    onChanged: (v) => setState(() => _quality = v),
                  ),
                  SwitchRow(
                    label: tr(zh: '保留拍摄信息 (EXIF)', en: 'Keep photo info (EXIF)'),
                    value: _keepExif,
                    onChanged: (v) => setState(() => _keepExif = v),
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
