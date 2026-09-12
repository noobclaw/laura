import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../models.dart';
import 'widgets.dart';

/// The per-frame alignment report — the thing the competitors do not show.
///
/// Every frame gets the same four numbers, and every rejected frame gets a
/// reason plus what to do about it. It stays available on the free tier: it
/// is the reason to choose this app, not an upsell.
class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key, required this.outcome});
  final StackOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final failed = outcome.reports.where((r) => !r.ok).toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '逐帧报告', en: 'Per-frame report'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              failed.isEmpty
                  ? tr(
                      zh: '全部 ${outcome.reports.length} 张都对上了。',
                      en: 'All ${outcome.reports.length} frames lined up.',
                    )
                  : tr(
                      zh: '${outcome.reports.length} 张里有 ${failed.length} 张没能对齐,下面写明了原因。',
                      en: '${failed.length} of ${outcome.reports.length} frames could not be aligned. The reasons are below.',
                    ),
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 16),
            for (final (i, r) in outcome.reports.indexed)
              RiseIn(index: i, child: _ReportCard(report: r)),
            const SizedBox(height: 8),
            Text(
              tr(
                zh: '残差 = 匹配上的星点在对齐之后与参考帧的平均偏差,单位像素。低于 1 px 已经很好。',
                en: 'Residual = the average distance, in pixels, between matched stars and where the reference frame puts them after alignment. Under 1 px is good.',
              ),
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});
  final FrameReport report;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final failed = !report.ok;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(report.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                ),
                if (report.isReference)
                  StatusPill(
                    label: tr(zh: '参考帧', en: 'REFERENCE'),
                    color: AstroColors.reference,
                    icon: Icons.center_focus_strong,
                  )
                else if (failed)
                  StatusPill(
                    label: tr(zh: '已排除', en: 'EXCLUDED'),
                    color: AstroColors.bad,
                    icon: Icons.cancel_outlined,
                  )
                else
                  StatusPill(
                    color: scoreColor(report.score),
                    icon: Icons.check_circle_outline,
                    child: CountUpText(report.score, prefix: tr(zh: '质量 ', en: 'SCORE ')),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (report.isReference)
              _Metrics(items: [
                _Metric(tr(zh: '检出星点', en: 'Stars found'), value: report.starsDetected),
                _Metric(tr(zh: '角色', en: 'Role'), text: tr(zh: '基准', en: 'Baseline')),
              ])
            else if (failed)
              _Metrics(items: [
                _Metric(tr(zh: '检出星点', en: 'Stars found'), value: report.starsDetected),
                _Metric(tr(zh: '匹配', en: 'Matched'), value: report.matchedStars),
              ])
            else
              _Metrics(items: [
                _Metric(tr(zh: '检出星点', en: 'Stars found'), value: report.starsDetected),
                _Metric(tr(zh: '匹配', en: 'Matched'), value: report.matchedStars),
                _Metric(tr(zh: '残差', en: 'Residual'),
                    value: report.rmsPixels, decimals: 2, unit: ' px'),
                _Metric(tr(zh: '位移', en: 'Shift'),
                    value: report.shiftPixels, decimals: 1, unit: ' px'),
                _Metric(tr(zh: '旋转', en: 'Rotation'),
                    value: report.rotationDegrees, decimals: 2, unit: '°'),
              ]),
            if (failed) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AstroColors.bad.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alignFailureText(report.failure!),
                        style: text.bodyMedium?.copyWith(color: cs.onSurface, height: 1.35)),
                    const SizedBox(height: 4),
                    Text(alignFailureHint(report.failure!),
                        style: text.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant, height: 1.35)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One metric: a label, and either a number that rolls into place ([value]
/// with [decimals] and a [unit]) or a fixed string ([text]).
class _Metric {
  const _Metric(this.label, {this.value, this.decimals = 0, this.unit = '', this.text});
  final String label;
  final num? value;
  final int decimals;
  final String unit;
  final String? text;
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.items});
  final List<_Metric> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 22,
      runSpacing: 12,
      children: [
        for (final m in items)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.value != null)
                CountUpText(m.value!,
                    decimals: m.decimals, suffix: m.unit, ms: 700, style: text.titleMedium)
              else
                Text(m.text ?? '', style: text.titleMedium),
              Text(m.label, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
      ],
    );
  }
}
