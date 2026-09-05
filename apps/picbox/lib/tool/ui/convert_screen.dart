import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../engine/jobs.dart';
import '../models.dart';
import '../pro.dart';
import '../store.dart';
import 'tool_flow.dart';
import 'widgets.dart';

/// Format conversion. JPEG / PNG / WebP / HEIC in → JPEG / PNG / WebP out.
/// Transparent PNG/WebP → JPEG goes through Dart so the alpha is composited
/// on white (the native encoders would leave black).
class ConvertScreen extends StatefulWidget {
  const ConvertScreen({super.key, required this.store});
  final PicboxStore store;

  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  ImageFormat _format = ImageFormat.jpeg;
  int _quality = 90;
  bool _keepExif = true;

  static const _key = 'convert';

  @override
  void initState() {
    super.initState();
    final s = widget.store.settingsFor(_key);
    if (s != null) {
      _format = ImageFormatX.fromName(s['format'] as String?);
      if (!_format.writable) _format = ImageFormat.jpeg;
      _quality = (s['quality'] as num?)?.toInt() ?? 90;
      _keepExif = s['keepExif'] as bool? ?? true;
    }
  }

  void _remember() => widget.store.rememberSettings(_key, {
        'format': _format.name,
        'quality': _quality,
        'keepExif': _keepExif,
      });

  Future<JobResult> _runOne(SourceImage src, RunContext ctx) async {
    final fmt = _format;
    final path = ctx.pathFor(src, fmt.extension);
    final probe = await probeFile(src.path);
    final needsWhiteFill = fmt == ImageFormat.jpeg && probe.info.hasAlpha;
    if (!needsWhiteFill) {
      final bytes = await nativeEncode(src.path,
          format: fmt, quality: _quality, keepExif: _keepExif, srcW: src.width, srcH: src.height);
      await File(path).writeAsBytes(bytes, flush: true);
      final p = await probeFile(path);
      return JobResult(
        source: src,
        outputPath: path,
        outputBytes: p.bytes,
        outputWidth: p.info.width,
        outputHeight: p.info.height,
        outputFormat: fmt,
        note: src.shownFormat == fmt ? tr(zh: '格式相同,已重新编码', en: 'Same format, re-encoded') : null,
      );
    }
    final out = await runDartJob(DartJobSpec(
      inputPath: src.path,
      outputPath: path,
      format: fmt,
      quality: _quality,
      keepMetadata: _keepExif,
      edit: const DartEdit(fillWhiteIfAlpha: true),
    ));
    return JobResult(
      source: src,
      outputPath: path,
      outputBytes: out.bytes,
      outputWidth: out.width,
      outputHeight: out.height,
      outputFormat: fmt,
      note: tr(zh: '透明区域已填白', en: 'Transparency filled with white'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ToolScaffold(
      kind: ToolKind.convert,
      store: widget.store,
      runOne: _runOne,
      onBeforeRun: _remember,
      options: (context, images) {
        final counts = <ImageFormat, int>{};
        for (final s in images) {
          counts.update(s.shownFormat, (v) => v + 1, ifAbsent: () => 1);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final e in counts.entries)
                      Chip(
                        avatar: Icon(Icons.image_outlined, size: 16, color: cs.onSurfaceVariant),
                        label: Text('${e.key.label} × ${e.value}'),
                      ),
                    Chip(
                      avatar: Icon(Icons.arrow_forward_rounded, size: 16, color: cs.primary),
                      label: Text(_format.label),
                      backgroundColor: cs.primaryContainer,
                    ),
                  ],
                ),
              ),
            SectionCard(
              title: tr(zh: '转换为', en: 'Convert to'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormatChoice(
                    value: _format,
                    pro: widget.store.pro,
                    onChanged: (f) => setState(() => _format = f ?? ImageFormat.jpeg),
                    onProNeeded: () => showProSheet(context,
                        reason: tr(zh: 'WebP 导出是 Pro 功能。', en: 'WebP export is a Pro feature.')),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    switch (_format) {
                      ImageFormat.jpeg => tr(zh: '兼容性最好;不支持透明,透明区域填白', en: 'Most compatible; no transparency (filled white)'),
                      ImageFormat.png => tr(zh: '无损、支持透明;文件较大', en: 'Lossless with transparency; larger files'),
                      ImageFormat.webp => tr(zh: '体积小、支持透明;老设备可能不识别', en: 'Small with transparency; older devices may not open it'),
                      _ => '',
                    },
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  QualitySlider(
                    value: _quality,
                    enabled: _format != ImageFormat.png,
                    onChanged: (v) => setState(() => _quality = v),
                  ),
                  SwitchRow(
                    label: tr(zh: '保留拍摄信息 (EXIF)', en: 'Keep photo info (EXIF)'),
                    subtitle: _format == ImageFormat.webp
                        ? tr(zh: 'iOS 上 WebP 无法写入 EXIF', en: 'iOS cannot write EXIF into WebP')
                        : null,
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
