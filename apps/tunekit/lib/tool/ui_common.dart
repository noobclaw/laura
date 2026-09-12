import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';

/// Small shared pieces so every page speaks the same visual language.

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A single-select row of chips; gated items show a small lock and call
/// [onLocked] instead of selecting.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.items,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.isLocked,
    this.onLocked,
    this.scrollable = true,
  });

  final List<T> items;
  final T selected;
  final String Function(T) label;
  final void Function(T) onSelected;
  final bool Function(T)? isLocked;
  final void Function(T)? onLocked;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final it in items)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label(it)),
                if (isLocked?.call(it) ?? false) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.lock_outline, size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ],
            ),
            selected: it == selected,
            showCheckmark: false,
            onSelected: (_) {
              if (isLocked?.call(it) ?? false) {
                onLocked?.call(it);
              } else {
                onSelected(it);
              }
            },
          ),
        ),
    ];
    if (!scrollable) return Wrap(runSpacing: 8, children: chips);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: chips),
    );
  }
}

/// Warm empty / guidance state: icon in a tinted disc, a title, a line of
/// help and an optional action.
class GuidanceCard extends StatelessWidget {
  const GuidanceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.tint,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = tint ?? cs.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  color.withValues(alpha: 0.35),
                  color.withValues(alpha: 0.06),
                ]),
              ),
              child: Icon(icon, size: 30, color: color),
            ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// A number that rolls from its previous value to the new one instead of
/// jumping (the first build rolls up from zero). Tabular figures keep the
/// width steady while it counts. Honours the OS reduced-motion setting.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber(
    this.value, {
    super.key,
    this.decimals = 0,
    this.style,
    this.duration = const Duration(milliseconds: 650),
  });

  final double value;
  final int decimals;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final s = (style ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (!motionEnabled(context)) return Text(value.toStringAsFixed(decimals), style: s);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(v.toStringAsFixed(decimals), style: s),
    );
  }
}

/// Fade + rise entrance for the [index]-th item of a list, staggered 40 ms
/// per item so a freshly built list settles in top to bottom.
class StaggerIn extends StatelessWidget {
  const StaggerIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!motionEnabled(context)) return child;
    final delay = (40 * index).clamp(0, 320);
    return TweenAnimationBuilder<double>(
      key: ValueKey(index),
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + delay),
      curve: Interval(delay / (260 + delay), 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      ),
    );
  }
}

/// Press feedback for any tappable child: scales to [pressedScale] while the
/// pointer is down. Uses raw pointer events so the child's own gesture
/// handling (buttons, ink) is untouched.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.pressedScale = 0.94});
  final Widget child;
  final double pressedScale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final on = motionEnabled(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: on && _down ? widget.pressedScale : 1,
        duration: kMotionShort,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Standard cross-fade + slight scale for swapping one widget for another
/// (chord diagram, status pill, icons). Keys on the child's own key.
class SwapFade extends StatelessWidget {
  const SwapFade({super.key, required this.child, this.duration = kMotionMedium, this.slide = false});
  final Widget child;
  final Duration duration;

  /// Slide up a little as well as fading (for taller content).
  final bool slide;

  @override
  Widget build(BuildContext context) {
    if (!motionEnabled(context)) return child;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: slide
            ? SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
                child: child,
              )
            : ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(anim),
                child: child,
              ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.center,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }
}

/// A labelled number in a stat tile. Give [number] (and optionally
/// [decimals]) to roll the figure into place; [value] is shown as-is.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.color,
    this.unit,
    this.number,
    this.decimals = 0,
  });

  final String value;
  final String label;
  final String? unit;
  final Color? color;
  final double? number;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final numStyle = text.headlineSmall?.copyWith(color: color ?? cs.onSurface);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (number != null)
                AnimatedNumber(number!, decimals: decimals, style: numStyle)
              else
                Text(value, style: numStyle),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(unit!, style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// "Pro" pill used next to gated options.
class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: kBeatAmber.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('PRO',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: kBeatAmber,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              )),
    );
  }
}

/// Minutes and seconds as `12:05`.
String formatMinSec(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Short weekday label for chart axes.
String weekdayShort(DateTime d) {
  const zh = ['一', '二', '三', '四', '五', '六', '日'];
  const en = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
  return isZhLocale ? zh[d.weekday - 1] : en[d.weekday - 1];
}
