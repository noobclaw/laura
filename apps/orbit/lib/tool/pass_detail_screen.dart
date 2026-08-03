import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'models.dart';
import 'sky_painters.dart';
import 'store.dart';
import 'ui_common.dart';

/// One pass, in full: the arc across the dome, the three moments that matter,
/// and the point-by-point table for anyone aiming something more precise than
/// their eyes.
class PassDetailScreen extends StatefulWidget {
  const PassDetailScreen({
    super.key,
    required this.pass,
    required this.store,
    required this.onAlign,
  });

  final SatPass pass;
  final OrbitStore store;
  final void Function(SatPass pass) onAlign;

  @override
  State<PassDetailScreen> createState() => _PassDetailScreenState();
}

class _PassDetailScreenState extends State<PassDetailScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Index of the track sample nearest to now — only while the pass is actually
  /// overhead, so the dome does not sprout a "you are here" dot for a pass three
  /// days out.
  int? get _nowIndex {
    final pass = widget.pass;
    final now = DateTime.now();
    if (now.isBefore(pass.start) || now.isAfter(pass.end)) return null;
    var best = 0;
    var bestDiff = Duration(days: 999);
    for (var i = 0; i < pass.track.length; i++) {
      final d = pass.track[i].time.difference(now).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final pass = widget.pass;
    final scheme = Theme.of(context).colorScheme;
    final visibleSamples = pass.visibleSamples;

    return Scaffold(
      appBar: AppBar(
        title: Text(pass.displayName),
        actions: [
          IconButton(
            tooltip: tr(zh: '抬头对准', en: 'Align'),
            icon: const Icon(Icons.explore_outlined),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onAlign(pass);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: SkyDomePainter(
                        track: pass.track,
                        scheme: scheme,
                        nowIndex: _nowIndex,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _Legend(
                        color: kOrbitCyan,
                        label: tr(zh: '被阳光照到', en: 'Sunlit'),
                      ),
                      _Legend(
                        color: kEclipseViolet,
                        label: tr(zh: '进入地影', en: 'In Earth\'s shadow'),
                      ),
                      _Legend(
                        color: kSignalAmber,
                        label: tr(zh: '最高点', en: 'Culmination'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _MomentsCard(pass: pass),
          const SizedBox(height: 14),
          _VerdictCard(pass: pass, visibleSampleCount: visibleSamples.length),
          const SizedBox(height: 14),
          _TrackTable(pass: pass),
          const SizedBox(height: 18),
          Center(child: FreshnessChip(ageDays: widget.store.catalogAgeDays)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _MomentsCard extends StatelessWidget {
  const _MomentsCard({required this.pass});
  final SatPass pass;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Column(
          children: [
            _Moment(
              icon: Icons.north_east,
              label: tr(zh: '升起', en: 'Rises'),
              time: pass.start,
              bearing: pass.startAzimuth,
              elevation: null,
            ),
            const Divider(height: 26),
            _Moment(
              icon: Icons.vertical_align_top,
              label: tr(zh: '最高', en: 'Culminates'),
              time: pass.peak,
              bearing: pass.peakAzimuth,
              elevation: pass.peakElevation,
              accent: kSignalAmber,
            ),
            const Divider(height: 26),
            _Moment(
              icon: Icons.south_east,
              label: tr(zh: '落下', en: 'Sets'),
              time: pass.end,
              bearing: pass.endAzimuth,
              elevation: null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Moment extends StatelessWidget {
  const _Moment({
    required this.icon,
    required this.label,
    required this.time,
    required this.bearing,
    required this.elevation,
    this.accent,
  });

  final IconData icon;
  final String label;
  final DateTime time;
  final double bearing;
  final double? elevation;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.onSurfaceVariant;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              Text(
                formatBearing(bearing),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatClock(time, seconds: true),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (elevation != null)
              Text(
                '${tr(zh: '仰角', en: 'elev')} ${formatElevation(elevation!)}',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: accent ?? scheme.onSurfaceVariant),
              ),
          ],
        ),
      ],
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.pass, required this.visibleSampleCount});

  final SatPass pass;
  final int visibleSampleCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final partial = pass.visible && visibleSampleCount < pass.track.length;
    // The dome's cyan/violet split is about the *satellite* being lit; the badge
    // is about whether you can see it. They can legitimately disagree.

    final body = pass.visible
        ? (partial
            ? tr(
                zh: '这次过境只有一部分看得见——卫星中途飞进地球的影子里就会消失,别以为是自己看错了。',
                en: 'Only part of this pass is visible: the satellite flies into the Earth\'s shadow partway across and simply vanishes. That is expected, not your eyes.',
              )
            : tr(
                zh: '整段都被太阳照着,而你这边天已经够黑——从升起看到落下。',
                en: 'Sunlit throughout while your own sky is dark — watchable from rise to set.',
              ))
        : (pass.visibility == PassVisibility.daylight
            ? tr(
                zh: '卫星是被太阳照着的,但这个时段你这边天还亮 —— 白天的天空太耀眼,看不出来。用无线电或望远镜追踪仍然有意义。',
                en: 'The satellite is in full sunlight, but your own sky is bright at this hour — daylight simply drowns it out. Still useful if you are tracking by radio or scope.',
              )
            : tr(
                zh: '整段都在地球的影子里,再黑的天也看不见。用无线电或望远镜追踪仍然有意义。',
                en: "It stays inside the Earth's shadow for the whole pass, so no sky is dark enough to show it. Still useful if you are tracking by radio or scope.",
              ));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                VisibilityBadge(
                    visibility: pass.visibility,
                    magnitude: pass.brightestMagnitude),
                const Spacer(),
                Text(
                  '${tr(zh: '最近距离', en: 'Closest')} ${pass.peakRangeKm.round()} km',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(body,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5)),
            if (pass.brightestMagnitude != null) ...[
              const SizedBox(height: 10),
              Text(
                tr(
                  zh: '预计最亮 ${formatMagnitude(pass.brightestMagnitude)} 等——数值是按标准星等估算的,实际受大气与姿态影响。',
                  en: 'Estimated peak magnitude ${formatMagnitude(pass.brightestMagnitude)} — derived from published standard magnitudes; haze and attitude shift it either way.',
                ),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrackTable extends StatelessWidget {
  const _TrackTable({required this.pass});
  final SatPass pass;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Every third sample: dense enough to follow, short enough to scan.
    final rows = <PassSample>[];
    for (var i = 0; i < pass.track.length; i += 3) {
      rows.add(pass.track[i]);
    }
    if (rows.isNotEmpty && rows.last != pass.track.last) rows.add(pass.track.last);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(zh: '逐点数据', en: 'Point by point'),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                _cell(context, tr(zh: '时刻', en: 'Time'), header: true, flex: 3),
                _cell(context, tr(zh: '方位', en: 'Bearing'), header: true, flex: 4),
                _cell(context, tr(zh: '仰角', en: 'Elev'), header: true, flex: 2),
                _cell(context, tr(zh: '距离', en: 'Range'), header: true, flex: 3),
              ],
            ),
            const Divider(height: 14),
            for (final s in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    _cell(context, formatClock(s.time, seconds: true), flex: 3),
                    _cell(context, formatBearing(s.azimuthDeg), flex: 4),
                    _cell(
                      context,
                      formatElevation(s.elevationDeg),
                      flex: 2,
                      color: s.sunlit ? null : kEclipseViolet,
                    ),
                    _cell(context, '${s.rangeKm.round()} km', flex: 3),
                  ],
                ),
              ),
            Text(
              tr(
                zh: '紫色仰角 = 该时刻卫星在地影中,看不见。',
                en: 'Violet elevation = eclipsed at that instant, not visible.',
              ),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String text,
      {bool header = false, int flex = 1, Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: header
            ? Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                )
            : Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
      ),
    );
  }
}
