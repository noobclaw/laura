import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../engine/jobs.dart';
import '../engine/metadata.dart';
import '../engine/resize_math.dart';
import '../models.dart';
import '../store.dart';
import 'tool_flow.dart';
import 'widgets.dart';

/// Strip metadata: shows what each picture carries (camera, time, GPS…)
/// and removes all of it without re-encoding the pixels.
class MetadataScreen extends StatefulWidget {
  const MetadataScreen({super.key, required this.store});
  final PicboxStore store;

  @override
  State<MetadataScreen> createState() => _MetadataScreenState();
}

class _MetadataScreenState extends State<MetadataScreen> {
  final Map<String, MetadataReport> _reports = {};
  final Set<String> _loading = {};
  final Map<String, String> _failed = {};

  void _onImages(List<SourceImage> images) {
    for (final s in images) {
      if (_reports.containsKey(s.id) || _loading.contains(s.id)) continue;
      _loading.add(s.id);
      inspectFile(s.path)
          .then((r) {
            if (!mounted) return;
            setState(() {
              _loading.remove(s.id);
              _reports[s.id] = r;
            });
          })
          .catchError((Object e) {
            if (!mounted) return;
            setState(() {
              _loading.remove(s.id);
              _failed[s.id] = e.toString();
            });
          });
    }
  }

  Future<JobResult> _runOne(SourceImage src, RunContext ctx) async {
    final ext = src.format.extension;
    final path = ctx.pathFor(src, ext);
    final out = await runStripJob(src.path, path);
    final r = _reports[src.id];
    return JobResult(
      source: src,
      outputPath: path,
      outputBytes: out.bytes,
      outputWidth: out.width,
      outputHeight: out.height,
      outputFormat: src.format,
      note: r == null
          ? null
          : r.isEmpty
          ? tr(zh: '原本就没有元数据', en: 'Had no metadata')
          : tr(
              zh: '已移除 ${r.tagCount} 个标签${r.hasGps ? '(含 GPS)' : ''}',
              en: 'Removed ${r.tagCount} tags${r.hasGps ? ' (incl. GPS)' : ''}',
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ToolScaffold(
      kind: ToolKind.metadata,
      store: widget.store,
      runOne: _runOne,
      onImagesChanged: _onImages,
      options: (context, images) {
        if (images.isEmpty) {
          return SectionCard(
            title: tr(zh: '这个工具做什么', en: 'What this does'),
            child: Text(
              tr(
                zh: '照片里通常藏着拍摄地点(GPS)、时间、机型、软件等信息。这里会先列出每张图内嵌了什么,再全部移除。JPEG / PNG / WebP 无损,像素一个字节都不动;HEIC 会先转成 JPEG。',
                en: 'Pictures usually carry the place (GPS), time, device and software they came from. This lists what each file contains, then removes all of it. Lossless for JPEG / PNG / WebP — not a single pixel is touched; HEIC is converted to JPEG first.',
              ),
              style: text.bodyMedium?.copyWith(height: 1.45),
            ),
          );
        }
        final gpsCount = images
            .where((s) => _reports[s.id]?.hasGps ?? false)
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (gpsCount > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on_rounded, color: cs.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr(
                          zh: '$gpsCount 张图片带有拍摄地点',
                          en: '$gpsCount picture${gpsCount == 1 ? '' : 's'} carry a location',
                        ),
                        style: text.bodyMedium?.copyWith(
                          color: cs.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            for (final s in images) ...[
              _ReportCard(
                image: s,
                report: _reports[s.id],
                loading: _loading.contains(s.id),
                failure: _failed[s.id],
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.image,
    required this.report,
    required this.loading,
    this.failure,
  });
  final SourceImage image;
  final MetadataReport? report;
  final bool loading;
  final String? failure;

  String _label(String key) => switch (key) {
    'Make' => tr(zh: '厂商', en: 'Make'),
    'Model' => tr(zh: '机型', en: 'Model'),
    'LensModel' => tr(zh: '镜头', en: 'Lens'),
    'ExposureTime' => tr(zh: '快门', en: 'Shutter'),
    'FNumber' => tr(zh: '光圈', en: 'Aperture'),
    'ISOSpeedRatings' => 'ISO',
    'FocalLength' => tr(zh: '焦距', en: 'Focal length'),
    'DateTimeOriginal' => tr(zh: '拍摄时间', en: 'Taken'),
    'DateTime' => tr(zh: '修改时间', en: 'Modified'),
    'Software' => tr(zh: '软件', en: 'Software'),
    'Artist' => tr(zh: '作者', en: 'Artist'),
    'Copyright' => tr(zh: '版权', en: 'Copyright'),
    'ImageDescription' => tr(zh: '描述', en: 'Description'),
    'UserComment' => tr(zh: '备注', en: 'Comment'),
    'Orientation' => tr(zh: '方向', en: 'Orientation'),
    'GPSPosition' => tr(zh: '位置', en: 'Location'),
    'GPSAltitude' => tr(zh: '海拔', en: 'Altitude'),
    'GPSDateStamp' => tr(zh: 'GPS 日期', en: 'GPS date'),
    _ => key,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final r = report;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ImageThumb(path: image.path, size: 48, radius: 10),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        image.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
                      ),
                      Text(
                        describeImage(image),
                        style: text.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (r?.hasGps ?? false)
                  Icon(Icons.location_on_rounded, color: cs.error, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            if (failure != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 18, color: cs.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr(
                        zh: '读取元数据失败:$failure,仍可直接清除',
                        en: 'Could not read metadata: $failure — you can still strip it',
                      ),
                      style: text.bodySmall?.copyWith(color: cs.error),
                    ),
                  ),
                ],
              )
            else if (loading || r == null)
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr(zh: '正在读取…', en: 'Reading…'),
                    style: text.bodySmall,
                  ),
                ],
              )
            else if (r.isEmpty)
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: Colors.green.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tr(zh: '没有发现元数据', en: 'No metadata found'),
                    style: text.bodyMedium,
                  ),
                ],
              )
            else ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final b in r.blocks)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(b, style: text.labelSmall),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tr(
                        zh: '${r.tagCount} 个标签 · ${formatBytes(r.metaBytes)}',
                        en: '${r.tagCount} tags · ${formatBytes(r.metaBytes)}',
                      ),
                      style: text.labelSmall,
                    ),
                  ),
                ],
              ),
              if (r.entries.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final e in r.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(
                            _label(e.key),
                            style: text.bodySmall?.copyWith(
                              color: e.group == 'gps'
                                  ? cs.error
                                  : cs.onSurfaceVariant,
                              fontWeight: e.group == 'gps'
                                  ? FontWeight.w600
                                  : null,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: e.group == 'gps' ? cs.error : null,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
