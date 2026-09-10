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
            for (final r in outcome.reports) _ReportCard(report: r),
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
                    label: tr(zh: '质量 ${report.score}', en: 'SCORE ${report.score}'),
                    color: scoreColor(report.score),
                    icon: Icons.check_circle_outline,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (report.isReference)
              _Metrics(items: [
                (tr(zh: '检出星点', en: 'Stars found'), '${report.starsDetected}'),
                (tr(zh: '角色', en: 'Role'), tr(zh: '基准', en: 'Baseline')),
              ])
            else if (failed)
              _Metrics(items: [
                (tr(zh: '检出星点', en: 'Stars found'), '${report.starsDetected}'),
                (tr(zh: '匹配', en: 'Matched'), '${report.matchedStars}'),
              ])
            else
              _Metrics(items: [
                (tr(zh: '检出星点', en: 'Stars found'), '${report.starsDetected}'),
                (tr(zh: '匹配', en: 'Matched'), '${report.matchedStars}'),
                (tr(zh: '残差', en: 'Residual'), '${report.rmsPixels.toStringAsFixed(2)} px'),
                (tr(zh: '位移', en: 'Shift'), '${report.shiftPixels.toStringAsFixed(1)} px'),
                (tr(zh: '旋转', en: 'Rotation'), '${report.rotationDegrees.toStringAsFixed(2)}°'),
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

class _Metrics extends StatelessWidget {
  const _Metrics({required this.items});
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 22,
      runSpacing: 12,
      children: [
        for (final (label, value) in items)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: text.titleMedium),
              Text(label, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
      ],
    );
  }
}
