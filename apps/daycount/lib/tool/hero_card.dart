import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'flip_digit.dart';
import 'models.dart';

/// Press feedback for any tappable surface: a `Listener` (so the child's own
/// InkWell / FAB keeps its tap) that scales the child down while a pointer is
/// held. Zero duration under reduced motion.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.965});
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

/// Hero tag shared between the list / featured card and the detail page so
/// the emoji flies between screens.
String emojiHeroTag(CountdownEvent e) => 'daybird-emoji-${e.id}';

/// The "nearest day" card at the top of the home list — the app's hero.
/// Event accent as a gradient ground, the emoji big, and the day count as a
/// wall of split-flap digits ([FlipNumber]). On the day itself the digits
/// give way to a 🎉 and confetti drifts down the right side.
class FeaturedCard extends StatelessWidget {
  const FeaturedCard({
    super.key,
    required this.event,
    required this.status,
    required this.progress,
    required this.onTap,
  });

  final CountdownEvent event;
  final EventStatus status;
  final double? progress;
  final VoidCallback onTap;

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final color = event.color;
    final dark = Color.lerp(color, Colors.black, 0.32)!;
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black87;
    final s = status;
    final label = s.isToday
        ? tr(zh: '就是今天', en: 'Today!')
        : (s.isFuture ? tr(zh: '还有', en: 'in') : tr(zh: '已过去', en: 'past'));
    final text = Theme.of(context).textTheme;

    return PressScale(
      child: TweenAnimationBuilder<double>(
        // Re-keyed per event so a new featured day slides/fades in rather
        // than the old numbers being overwritten in place.
        key: ValueKey('featured-${event.id}'),
        tween: Tween(begin: 0, end: 1),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: child,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.38),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Material(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, dark],
                ),
              ),
              child: InkWell(
                onTap: onTap,
                splashColor: onColor.withValues(alpha: 0.12),
                highlightColor: onColor.withValues(alpha: 0.06),
                child: Stack(
                  children: [
                    // Soft highlight so the gradient has some depth.
                    Positioned(
                      right: -60,
                      top: -70,
                      child: IgnorePointer(
                        child: Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              Colors.white.withValues(alpha: 0.22),
                              Colors.white.withValues(alpha: 0),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    if (s.isToday)
                      const Positioned.fill(
                        child: IgnorePointer(child: ConfettiOverlay()),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: onColor.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Hero(
                                  tag: emojiHeroTag(event),
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: Text(
                                      event.emoji,
                                      style: const TextStyle(fontSize: 34),
                                    ),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              _Pill(text: label, fg: onColor),
                              if (event.pinned) ...[
                                const SizedBox(width: 6),
                                _Pill(
                                  icon: Icons.push_pin,
                                  text: tr(zh: '置顶', en: 'Pinned'),
                                  fg: onColor,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            event.title.isEmpty
                                ? tr(zh: '未命名', en: 'Untitled')
                                : event.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleLarge?.copyWith(
                              color: onColor,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (s.isToday)
                            _TodayBurst(onColor: onColor)
                          else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: FlipNumber(
                                    value: s.absDays,
                                    textColor: onColor,
                                    tileColor: (onColor == Colors.white
                                            ? Colors.black
                                            : Colors.white)
                                        .withValues(alpha: 0.18),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    tr(zh: '天', en: 'days'),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: onColor.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Icon(Icons.event_outlined,
                                  size: 16,
                                  color: onColor.withValues(alpha: 0.8)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${s.target.year}-${_two(s.target.month)}-${_two(s.target.day)} '
                                  '${weekdayLabel(s.target)}'
                                  '${event.yearlyRepeat ? ' · ${tr(zh: '每年', en: 'yearly')}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: onColor.withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (progress != null) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: progress),
                                duration: reduce
                                    ? Duration.zero
                                    : const Duration(milliseconds: 700),
                                curve: Curves.easeOutCubic,
                                builder: (context, v, _) =>
                                    LinearProgressIndicator(
                                  value: v,
                                  minHeight: 6,
                                  backgroundColor:
                                      onColor.withValues(alpha: 0.18),
                                  valueColor: AlwaysStoppedAnimation(onColor),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.fg, this.icon});
  final String text;
  final Color fg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// The 🎉 that replaces the digits on the day itself, popping in.
class _TodayBurst extends StatelessWidget {
  const _TodayBurst({required this.onColor});
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, t, child) =>
          Transform.scale(scale: t, alignment: Alignment.centerLeft, child: child),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text('🎉', style: TextStyle(fontSize: 84, height: 1.05)),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              tr(zh: '就是今天', en: 'Today!'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: onColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Confetti and star sparks drifting down the right half of the hero card.
/// Only mounted on "today" cards. Under reduced motion it paints one still
/// frame instead of looping.
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key});

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    _particles = List.generate(30, (i) => _Particle.random(rnd, i));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _ctrl.stop();
      _ctrl.value = 0.37;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ConfettiPainter(_particles, _ctrl),
      willChange: true,
    );
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.speed,
    required this.phase,
    required this.size,
    required this.spin,
    required this.sway,
    required this.color,
    required this.kind,
  });

  factory _Particle.random(math.Random r, int i) {
    const palette = [
      Color(0xFFFFFFFF),
      Color(0xFFFFD166),
      Color(0xFFFFE8A3),
      Color(0xFFFFB3C1),
      Color(0xFFBDE0FE),
    ];
    return _Particle(
      x: 0.5 + r.nextDouble() * 0.5, // right half of the card
      speed: 0.7 + r.nextDouble() * 0.9,
      phase: r.nextDouble(),
      size: 4 + r.nextDouble() * 5,
      spin: (r.nextDouble() - 0.5) * 8,
      sway: 0.02 + r.nextDouble() * 0.05,
      color: palette[i % palette.length],
      kind: i % 4, // 0 rect, 1 circle, 2 star, 3 ribbon
    );
  }

  final double x, speed, phase, size, spin, sway;
  final Color color;
  final int kind;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.t) : super(repaint: t);
  final List<_Particle> particles;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      final u = (t.value * p.speed + p.phase) % 1.0; // 0 top → 1 bottom
      final y = (u * 1.25 - 0.15) * size.height;
      final x = (p.x + math.sin(u * math.pi * 4 + p.phase * 6) * p.sway) *
          size.width;
      // Fade in at the top edge, fade out near the bottom.
      final alpha = (u < 0.1 ? u / 0.1 : (u > 0.8 ? (1 - u) / 0.2 : 1.0))
          .clamp(0.0, 1.0);
      paint.color = p.color.withValues(alpha: 0.9 * alpha);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(u * p.spin);
      switch (p.kind) {
        case 0:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset.zero, width: p.size * 1.6, height: p.size),
              const Radius.circular(1.5),
            ),
            paint,
          );
        case 1:
          canvas.drawCircle(Offset.zero, p.size * 0.5, paint);
        case 2:
          _star(canvas, paint, p.size * 0.9);
        default:
          // A short ribbon: a bent bar.
          final path = Path()
            ..moveTo(-p.size, 0)
            ..quadraticBezierTo(0, -p.size * 0.8, p.size, 0)
            ..lineTo(p.size, p.size * 0.35)
            ..quadraticBezierTo(0, -p.size * 0.45, -p.size, p.size * 0.35)
            ..close();
          canvas.drawPath(path, paint);
      }
      canvas.restore();
    }
  }

  static void _star(Canvas c, Paint paint, double r) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final rr = i.isEven ? r : r * 0.42;
      final a = i * math.pi / 4 - math.pi / 2;
      final pt = Offset(math.cos(a) * rr, math.sin(a) * rr);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    c.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.particles != particles;
}

/// The Daybird mark — a geometric bird carrying a dot (the day) — drawn with
/// the same geometry as the launcher icon. Used by the empty state so the
/// first screen a new user sees already looks like the app they installed.
class BirdMark extends StatelessWidget {
  const BirdMark({super.key, this.size = 120});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BirdPainter()),
    );
  }
}

class _BirdPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 1024;
    canvas.scale(k);
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFF8A73), Color(0xFFE7625F), Color(0xFFD1402F)],
      ).createShader(const Rect.fromLTWH(0, 0, 1024, 1024));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 1024, 1024), const Radius.circular(230)),
      bg,
    );
    final white = Paint()..color = Colors.white;
    final outline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 44
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final bird = birdPath();
    canvas.drawPath(bird, outline);
    canvas.drawPath(bird, white);
    // Wing.
    canvas.save();
    canvas.translate(430, 560);
    canvas.rotate(-0.35);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 300, height: 130),
      Paint()..color = const Color(0xFFFFCFC3),
    );
    canvas.restore();
    // Eye.
    canvas.drawCircle(
        const Offset(672, 372), 18, Paint()..color = const Color(0xFFC93F30));
    // The day: a gold dot held at the beak.
    canvas.drawCircle(const Offset(878, 402), 74, white);
    canvas.drawCircle(
        const Offset(878, 402), 54, Paint()..color = const Color(0xFFFFC94D));
  }

  /// Body + head + beak + tail as one path so the stroke merges them.
  static Path birdPath() {
    final p = Path();
    // Body (tilted ellipse).
    p.addOval(Rect.fromCenter(
        center: const Offset(470, 570), width: 480, height: 340));
    // Head.
    p.addOval(Rect.fromCircle(center: const Offset(640, 410), radius: 132));
    // Beak.
    p.moveTo(745, 372);
    p.lineTo(836, 402);
    p.lineTo(745, 440);
    p.close();
    // Tail feathers.
    p.moveTo(300, 515);
    p.lineTo(118, 392);
    p.lineTo(196, 548);
    p.lineTo(300, 600);
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(_BirdPainter old) => false;
}
