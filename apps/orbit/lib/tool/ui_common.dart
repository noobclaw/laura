import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'models.dart';
import 'passes.dart';

/// Shared presentation bits — the formatting rules and the small components
/// every screen reuses, so spacing, radii and voice stay identical throughout.

String two(int n) => n.toString().padLeft(2, '0');

/// Wall-clock time, 24h. Satellite passes are a timetable; AM/PM ambiguity at
/// 5 in the morning is exactly the wrong kind of charm.
String formatClock(DateTime t, {bool seconds = false}) => seconds
    ? '${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
    : '${two(t.hour)}:${two(t.minute)}';

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  if (m >= 60) {
    return tr(zh: '${d.inHours} 小时 ${m % 60} 分', en: '${d.inHours}h ${m % 60}m');
  }
  return tr(zh: '$m 分 $s 秒', en: '${m}m ${two(s)}s');
}

/// Countdown for the hero. Anything an hour or more out carries explicit units —
/// a bare "02:27" beside a departure time of 10:48 reads as a clock time, which
/// is the one thing this number must never be mistaken for. Inside the last
/// hour it becomes a mm:ss the way a countdown should.
String formatCountdown(Duration d) {
  if (d.isNegative) return tr(zh: '正在过境', en: 'Passing now');
  if (d.inDays >= 1) {
    return tr(
      zh: '${d.inDays} 天 ${d.inHours % 24} 小时',
      en: '${d.inDays}d ${d.inHours % 24}h',
    );
  }
  if (d.inHours >= 1) {
    return tr(
      zh: '${d.inHours} 小时 ${d.inMinutes % 60} 分',
      en: '${d.inHours}h ${d.inMinutes % 60}m',
    );
  }
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

/// Re-exported so screens only need one presentation import.
String compassPointOf(double azimuthDeg) => compassPoint(azimuthDeg);

String formatBearing(double azimuthDeg) =>
    '${compassPoint(azimuthDeg)} ${azimuthDeg.round()}°';

String formatElevation(double elevationDeg) => '${elevationDeg.round()}°';

String formatMagnitude(double? mag) =>
    mag == null ? '—' : (mag >= 0 ? '+' : '') + mag.toStringAsFixed(1);

String formatDayHeader(DateTime day) {
  final today = DateTime.now();
  final midnight = DateTime(today.year, today.month, today.day);
  final diff = DateTime(day.year, day.month, day.day).difference(midnight).inDays;
  if (diff == 0) return tr(zh: '今天', en: 'Today');
  if (diff == 1) return tr(zh: '明天', en: 'Tomorrow');
  return tr(
    zh: '${day.month} 月 ${day.day} 日',
    en: '${_monthEn(day.month)} ${day.day}',
  );
}

String _monthEn(int m) => const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][m - 1];

/// A first-run screen should tell you what this app is for and give you the one
/// button that starts it — not a bare line of grey text.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kOrbitCyan.withValues(alpha: 0.28),
                    kOrbitCyan.withValues(alpha: 0.04),
                  ],
                ),
              ),
              child: Icon(icon, size: 46, color: kOrbitCyan),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// How old the orbital elements are, stated plainly wherever a prediction is.
class FreshnessChip extends StatelessWidget {
  const FreshnessChip({super.key, required this.ageDays, this.compact = false});

  final double ageDays;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = freshnessOf(ageDays);
    final color = switch (level) {
      ElementFreshness.fresh => kOrbitCyan,
      ElementFreshness.aging => kSignalAmber,
      ElementFreshness.stale => scheme.error,
    };
    final days = ageDays.isFinite ? ageDays.round() : 0;
    final age = tr(zh: '$days 天前', en: '${days}d old');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.satellite_alt, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            compact ? age : '${tr(zh: '轨道数据', en: 'Orbit data')} · $age · ${freshnessLabel(level)}',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// A labelled number. Used in rows of three or four; the value carries the
/// weight and the label stays quiet.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.accent,
    this.onLight = false,
  });

  final String label;
  final String value;
  final Color? accent;

  /// True when sitting on the hero gradient, where the palette is fixed light
  /// on dark regardless of the app's brightness.
  final bool onLight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelColor =
        onLight ? Colors.white.withValues(alpha: 0.68) : scheme.onSurfaceVariant;
    final valueColor = accent ?? (onLight ? Colors.white : scheme.onSurface);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: labelColor,
                letterSpacing: 0.4,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: valueColor, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Section divider used down the pass list.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Row(
        children: [
          Text(
            text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Visibility verdict, colour-coded. Three states, because "above the horizon"
/// and "actually watchable" are different claims — and because the two ways of
/// being unwatchable have different fixes. Telling someone their pass is "in
/// shadow" when the real problem is that it happens at noon is a lie they can
/// catch just by looking outside.
class VisibilityBadge extends StatelessWidget {
  const VisibilityBadge({super.key, required this.visibility, this.magnitude});

  final PassVisibility visibility;
  final double? magnitude;

  @override
  Widget build(BuildContext context) {
    final color = switch (visibility) {
      PassVisibility.visible => kOrbitCyan,
      PassVisibility.eclipsed => kEclipseViolet,
      PassVisibility.daylight => kSignalAmber,
    };
    final label = switch (visibility) {
      PassVisibility.visible => magnitude == null
          ? tr(zh: '肉眼可见', en: 'Naked eye')
          : '${tr(zh: '肉眼可见', en: 'Naked eye')} · ${formatMagnitude(magnitude)}',
      PassVisibility.eclipsed => tr(zh: '在地影中', en: 'In shadow'),
      PassVisibility.daylight => tr(zh: '白天,天太亮', en: 'Daylight'),
    };
    final icon = switch (visibility) {
      PassVisibility.visible => Icons.visibility,
      PassVisibility.eclipsed => Icons.dark_mode,
      PassVisibility.daylight => Icons.wb_sunny_outlined,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
