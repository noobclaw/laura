import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../engine/stack.dart';
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
    final trails = outcome.mode.isTrails;
    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '逐帧报告', en: 'Per-frame report'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              trails
                  ? tr(
                      zh: '星轨模式不做星点对齐,${outcome.reports.length} 张按原样合成。下面的星点数可以看出中途有没有起云。',
                      en: 'Star trail mode does not align on stars: all ${outcome.reports.length} frames went in exactly as shot. The star counts below are where cloud creeping in shows up.',
                    )
                  : failed.isEmpty
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
            if (outcome.calibrated) ...[
              const SizedBox(height: 10),
              Text(
                tr(
                  zh: '本次已做校准:暗场 ${outcome.darkFrames} 张、平场 ${outcome.flatFrames} 张,已在对齐前从每一帧里扣除/校正。',
                  en: 'Calibrated with ${outcome.darkFrames} dark and ${outcome.flatFrames} flat frames, applied to every frame before alignment.',
                ),
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
              ),
            ],
            if (outcome.skippedCalibrationFrames > 0) ...[
              const SizedBox(height: 6),
              Text(
                tr(
                  zh: '另有 ${outcome.skippedCalibrationFrames} 张校准帧读不出来,没有参与合成 —— 主帧是用剩下的那些算的。',
                  en: '${outcome.skippedCalibrationFrames} calibration frame(s) could not be read and were left out — the masters were built from the rest.',
                ),
                style: text.bodySmall
                    ?.copyWith(color: AstroColors.of(context).warn, height: 1.4),
              ),
            ],
            const SizedBox(height: 16),
            for (final (i, r) in outcome.reports.indexed)
              RiseIn(index: i, child: _ReportCard(report: r)),
            const SizedBox(height: 8),
            Text(
              trails
                  ? tr(
                      zh: '星轨模式没有残差可报 —— 每一帧都按原样参与合成,取每个像素最亮的一次。',
                      en: 'There is no residual to report in star trail mode: every frame goes in as shot, and each pixel keeps the brightest value it ever had.',
                    )
                  : tr(
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
    final status = AstroColors.of(context);
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
                    color: status.reference,
                    icon: Icons.center_focus_strong,
                  )
                else if (failed)
                  StatusPill(
                    label: tr(zh: '已排除', en: 'EXCLUDED'),
                    color: status.bad,
                    icon: Icons.cancel_outlined,
                  )
                else
                  StatusPill(
                    color: scoreColor(context, report.score),
                    icon: Icons.check_circle_outline,
                    child: CountUpText(report.score, prefix: tr(zh: '质量 ', en: 'SCORE ')),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (report.unaligned && !failed)
              // No transform was fitted, so matched / residual / shift /
              // rotation would all be a printed zero pretending to be a
              // measurement.
              _Metrics(items: [
                _Metric(tr(zh: '检出星点', en: 'Stars found'), value: report.starsDetected),
                if (report.fwhmPixels > 0)
                  _Metric(tr(zh: '星点宽度', en: 'Star FWHM'),
                      value: report.fwhmPixels, decimals: 1, unit: ' px'),
                _Metric(tr(zh: '对齐', en: 'Alignment'),
                    text: tr(zh: '未对齐', en: 'None')),
              ])
            else if (report.isReference)
              _Metrics(items: [
                _Metric(tr(zh: '检出星点', en: 'Stars found'), value: report.starsDetected),
                if (report.fwhmPixels > 0)
                  _Metric(tr(zh: '星点宽度', en: 'Star FWHM'),
                      value: report.fwhmPixels, decimals: 1, unit: ' px'),
                _Metric(tr(zh: '角色', en: 'Role'), text: tr(zh: '基准', en: 'Baseline')),
              ])
            else if (failed)
              _Metrics(items: [
                _Metric(tr(zh: '检出星点', en: 'Stars found'), value: report.starsDetected),
                _Metric(tr(zh: '匹配', en: 'Matched'), value: report.matchedStars),
                if (report.fwhmPixels > 0)
                  _Metric(tr(zh: '星点宽度', en: 'Star FWHM'),
                      value: report.fwhmPixels, decimals: 1, unit: ' px'),
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
                if (report.fwhmPixels > 0)
                  _Metric(tr(zh: '星点宽度', en: 'Star FWHM'),
                      value: report.fwhmPixels, decimals: 1, unit: ' px'),
                if (report.fwhmPixels > 0)
                  _Metric(tr(zh: '拉长', en: 'Elongation'),
                      value: report.ovalityPixels, decimals: 1, unit: ' px'),
              ]),
            if (failed) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: status.bad.withValues(alpha: 0.12),
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
