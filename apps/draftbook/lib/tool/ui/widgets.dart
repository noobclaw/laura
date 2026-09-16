import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../models.dart';
import 'ink_mark.dart';

/// Press feedback on anything tappable that is not a Material button
/// (PIPELINE 视觉标准 10①). Scales down under the finger, springs back.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A count that rolls up to its value instead of snapping (视觉标准 10③).
class RollingCount extends StatelessWidget {
  const RollingCount({
    super.key,
    required this.value,
    this.style,
    this.suffix = '',
    this.rollIn = true,
    this.duration = const Duration(milliseconds: 600),
  });

  final int value;
  final TextStyle? style;
  final String suffix;

  /// Count up from zero the first time this widget is built. Pass false where
  /// the number changes on every keystroke — a live count must not chase its
  /// own tail.
  final bool rollIn;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: rollIn ? 0 : value.toDouble(),
        end: value.toDouble(),
      ),
      duration: reduce ? Duration.zero : duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) =>
          Text('${groupedCount(v.round())}$suffix', style: style),
    );
  }
}

/// A labelled figure — the same shape wherever the app shows a number, so the
/// stats sheet, the project card and the editor bar read as one system.
class StatPill extends StatelessWidget {
  const StatPill({
    super.key,
    required this.label,
    required this.value,
    this.tone,
    this.icon,
  });

  final String label;
  final String value;
  final Color? tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = tone ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}

/// Empty states with a drawn mark, a line of guidance and (optionally) the
/// action that fills them — never a single cold line of text (视觉标准 5).
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.title,
    required this.body,
    this.action,
    this.markSize = 108,
  });

  final String title;
  final String body;
  final Widget? action;
  final double markSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 480),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DraftbookMark(size: markSize),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
              ),
              if (action != null) ...[
                const SizedBox(height: 22),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin progress rail used for book and daily targets.
class ProgressRail extends StatelessWidget {
  const ProgressRail({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
  });

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: c.withValues(alpha: 0.16),
          valueColor: AlwaysStoppedAnimation(c),
        ),
      ),
    );
  }
}

/// A coloured dot for [SceneStatus], with its meaning available to assistive
/// tech rather than carried by colour alone.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status, this.size = 10});

  final SceneStatus status;
  final double size;

  static Color colorOf(BuildContext context, SceneStatus s) {
    final cs = Theme.of(context).colorScheme;
    return switch (s) {
      SceneStatus.todo => cs.onSurfaceVariant.withValues(alpha: 0.45),
      SceneStatus.drafting => cs.primary,
      SceneStatus.done => cs.tertiary,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: sceneStatusLabel(status),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorOf(context, status),
        ),
      ),
    );
  }
}

/// "3 分钟前 / 2 天前" — relative times, in both languages, without pulling in
/// an i18n date package.
String relativeTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inMinutes < 1) return tr(zh: '刚刚', en: 'just now');
  if (d.inMinutes < 60) {
    final m = d.inMinutes;
    return tr(zh: '$m 分钟前', en: m == 1 ? '1 minute ago' : '$m minutes ago');
  }
  if (d.inHours < 24) {
    final h = d.inHours;
    return tr(zh: '$h 小时前', en: h == 1 ? '1 hour ago' : '$h hours ago');
  }
  if (d.inDays < 30) {
    final days = d.inDays;
    return tr(zh: '$days 天前', en: days == 1 ? 'yesterday' : '$days days ago');
  }
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// Words, phrased for the current language ("12,480 字" / "12,480 words").
String wordsLabel(int n) =>
    tr(zh: '${groupedCount(n)} 字', en: '${groupedCount(n)} words');
