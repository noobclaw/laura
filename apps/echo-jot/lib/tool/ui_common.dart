import 'package:flutter/material.dart';

import '../core/l10n.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// "1:04" / "12:03" — tabular figures in the theme keep it from jittering.
String formatElapsed(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${_two(s)}';
}

/// "今天 09:14" / "Today 09:14", or "07/28 21:03" for older notes.
String formatNoteStamp(DateTime when) {
  final now = DateTime.now();
  final t = '${_two(when.hour)}:${_two(when.minute)}';
  final sameDay =
      now.year == when.year && now.month == when.month && now.day == when.day;
  if (sameDay) return '${tr(zh: '今天', en: 'Today')} $t';
  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday = yesterday.year == when.year &&
      yesterday.month == when.month &&
      yesterday.day == when.day;
  if (isYesterday) return '${tr(zh: '昨天', en: 'Yesterday')} $t';
  return '${_two(when.month)}/${_two(when.day)} $t';
}

/// "42 字" / "42 words" — CJK counts characters, Latin counts words, and the
/// English form is singular when it should be.
String formatLength(int units, {required bool cjk}) {
  if (cjk) return tr(zh: '$units 字', en: '$units chars');
  return tr(zh: '$units 词', en: units == 1 ? '1 word' : '$units words');
}

/// A warm, consistent empty state: an icon in a soft tinted circle, a heading,
/// and a supporting line — so a blank list feels designed, not abandoned.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Centred when there is room, scrollable when there isn't (short screens,
    // landscape, big system font) — an empty state must never clip.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.primary.withValues(alpha: 0.22),
                          cs.primary.withValues(alpha: 0.08),
                        ],
                      ),
                    ),
                    child: Icon(icon, size: 38, color: cs.primary),
                  ),
                  const SizedBox(height: 18),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.65),
                          height: 1.45,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live loudness bars driven by the recognizer's RMS callback — the app's
/// "we're listening" signal. Flat bars simply mean silence, never a crash.
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.levels});

  final List<double> levels;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final level in levels)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                width: 4,
                height: 4 + level * 34,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    cs.primary.withValues(alpha: 0.45),
                    cs.primary,
                    level,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The app's signature control: a large mic button with a soft pulsing ring
/// while a session is live.
class MicButton extends StatefulWidget {
  const MicButton({super.key, required this.listening, required this.onTap});

  final bool listening;
  final VoidCallback onTap;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (widget.listening) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant MicButton old) {
    super.didUpdateWidget(old);
    if (widget.listening && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.listening && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = widget.listening ? cs.error : cs.primary;
    return SizedBox(
      width: 140,
      height: 128,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.listening)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = _pulse.value;
                return Container(
                  width: 96 + t * 42,
                  height: 96 + t * 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: (1 - t) * 0.20),
                  ),
                );
              },
            ),
          Semantics(
            button: true,
            label: widget.listening
                ? tr(zh: '停止听写', en: 'Stop dictation')
                : tr(zh: '开始听写', en: 'Start dictation'),
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(accent, Colors.white, 0.18)!,
                      accent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.32),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  widget.listening ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 42,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
