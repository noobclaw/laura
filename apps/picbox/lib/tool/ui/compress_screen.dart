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

enum _Mode { quality, size }

enum _Unit { kb, mb }

/// Compress: by quality or to a target file size. Native codec path.
class CompressScreen extends StatefulWidget {
  const CompressScreen({super.key, required this.store});
  final PicboxStore store;

  @override
  State<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends State<CompressScreen> {
  _Mode _mode = _Mode.quality;
  int _quality = 80;
  int _target = 500;
  _Unit _unit = _Unit.kb;
  ImageFormat? _format; // null = keep source format (HEIC → JPEG)
  bool _keepExif = true;

  static const _key = 'compress';

  @override
  void initState() {
    super.initState();
    final s = widget.store.settingsFor(_key);
    if (s != null) {
      _mode = s['mode'] == 'size' ? _Mode.size : _Mode.quality;
      _quality = (s['quality'] as num?)?.toInt() ?? 80;
      _target = (s['target'] as num?)?.toInt() ?? 500;
      _unit = s['unit'] == 'mb' ? _Unit.mb : _Unit.kb;
      final f = s['format'] as String?;
      _format = f == null ? null : ImageFormatX.fromName(f);
      _keepExif = s['keepExif'] as bool? ?? true;
    }
  }

  void _remember() => widget.store.rememberSettings(_key, {
        'mode': _mode.name,
        'quality': _quality,
        'target': _target,
        'unit': _unit.name,
        'format': _format?.name,
        'keepExif': _keepExif,
      });

  int get _targetBytes => _target * (_unit == _Unit.kb ? 1024 : 1024 * 1024);

  ImageFormat _outFormat(SourceImage s) {
    final f = _format ?? (s.format == ImageFormat.heic ? ImageFormat.jpeg : s.format);
    return f.writable ? f : ImageFormat.jpeg;
  }

  Future<JobResult> _runOne(SourceImage src, RunContext ctx) async {
    final fmt = _outFormat(src);
    final path = ctx.pathFor(src, fmt.extension);
    // Transparent PNG/WebP → JPEG: flatten on white first (native = black).
    final input = await ensureOpaqueSource(src, fmt, ctx.outDir);
    String? note;
    List<int> bytes;
    if (_mode == _Mode.quality) {
      if (fmt == ImageFormat.png) {
        // PNG is lossless: the slider cannot shrink it. Re-encode as-is but
        // say so instead of pretending.
        note = tr(zh: 'PNG 无损,画质设置无效', en: 'PNG is lossless; quality has no effect');
      }
      bytes = await nativeEncode(input,
          format: fmt, quality: _quality, keepExif: _keepExif, srcW: src.width, srcH: src.height);
    } else {
      final r = await nativeCompressToSize(src,
          format: fmt, targetBytes: _targetBytes, keepExif: _keepExif, inputPath: input);
      bytes = r.bytes;
      if (!r.search.hitTarget) {
        note = tr(zh: '已尽力,仍略大于目标', en: 'Best effort; still above target');
      } else if (r.search.params.scale < 0.999) {
        note = tr(
            zh: '已缩小到 ${(r.search.params.scale * 100).round()}% 以达标',
            en: 'Scaled to ${(r.search.params.scale * 100).round()}% to hit the target');
      }
    }
    await File(path).writeAsBytes(bytes, flush: true);
    final p = await probeFile(path);
    return JobResult(
      source: src,
      outputPath: path,
      outputBytes: p.bytes,
      outputWidth: p.info.width,
      outputHeight: p.info.height,
      outputFormat: fmt,
      note: note,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ToolScaffold(
      kind: ToolKind.compress,
      store: widget.store,
      runOne: _runOne,
      onBeforeRun: _remember,
      blocker: _mode == _Mode.size && _target <= 0
          ? tr(zh: '请输入目标大小', en: 'Enter a target size')
          : null,
      options: (context, images) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: tr(zh: '压缩方式', en: 'Method'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_Mode>(
                  segments: [
                    ButtonSegment(value: _Mode.quality, label: Text(tr(zh: '按画质', en: 'By quality')), icon: const Icon(Icons.tune_rounded)),
                    ButtonSegment(value: _Mode.size, label: Text(tr(zh: '指定大小', en: 'Target size')), icon: const Icon(Icons.straighten_rounded)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: 14),
                if (_mode == _Mode.quality) ...[
                  QualitySlider(value: _quality, onChanged: (v) => setState(() => _quality = v)),
                  Text(
                    _quality >= 85
                        ? tr(zh: '几乎无损,适合存档', en: 'Near-lossless, good for archiving')
                        : _quality >= 60
                            ? tr(zh: '肉眼难辨,适合分享', en: 'Hard to tell apart, good for sharing')
                            : tr(zh: '明显压缩,体积最小', en: 'Visible compression, smallest files'),
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: IntField(
                          label: tr(zh: '每张不超过', en: 'Each image under'),
                          value: _target,
                          min: 1,
                          max: 100000,
                          onChanged: (v) => setState(() => _target = v ?? 0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SegmentedButton<_Unit>(
                        segments: const [
                          ButtonSegment(value: _Unit.kb, label: Text('KB')),
                          ButtonSegment(value: _Unit.mb, label: Text('MB')),
                        ],
                        selected: {_unit},
                        onSelectionChanged: (s) => setState(() => _unit = s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (v, u, l) in [(200, _Unit.kb, '200 KB'), (500, _Unit.kb, '500 KB'), (1, _Unit.mb, '1 MB'), (2, _Unit.mb, '2 MB')])
                        ActionChip(
                          label: Text(l),
                          onPressed: () => setState(() {
                            _target = v;
                            _unit = u;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      zh: '先降画质(最低 20),仍超标时再缩小尺寸。目标 ${formatBytes(_targetBytes)}。',
                      en: 'Quality is lowered first (down to 20), then the image is scaled down if still too large. Target ${formatBytes(_targetBytes)}.',
                    ),
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
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
                if (_format == null && images.any((s) => s.shownFormat == ImageFormat.heic))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(tr(zh: 'HEIC 会输出为 JPEG', en: 'HEIC will be written as JPEG'),
                        style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                SwitchRow(
                  label: tr(zh: '保留拍摄信息 (EXIF)', en: 'Keep photo info (EXIF)'),
                  subtitle: tr(zh: '关闭则同时去掉位置等元数据', en: 'Off also drops location and other metadata'),
                  value: _keepExif,
                  onChanged: (v) => setState(() => _keepExif = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
