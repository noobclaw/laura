import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'metronome_controller.dart';
import 'music/metronome_math.dart';
import 'pro.dart';
import 'store.dart';
import 'ui_common.dart';

class MetronomePage extends StatelessWidget {
  const MetronomePage({super.key, required this.store, required this.metro});

  final TuneKitStore store;
  final MetronomeController metro;

  void _pickSignature(BuildContext context, int index) {
    final sig = kTimeSignatures[index];
    if (!sig.free && !store.pro) {
      showProSheet(context,
          reason: tr(
            zh: '${sig.label} 拍号是 Pro 功能。免费版包含 2/4、3/4、4/4。',
            en: '${sig.label} is a Pro metre. Free includes 2/4, 3/4 and 4/4.',
          ));
      return;
    }
    store.setMetronome(sigIndex: index);
  }

  void _pickSubdivision(BuildContext context, int index) {
    final sub = Subdivision.values[index];
    if (!sub.free && !store.pro) {
      showProSheet(context,
          reason: tr(
            zh: '三连音与十六分音符细分是 Pro 功能。免费版包含四分与八分音符。',
            en: 'Triplet and sixteenth subdivisions are Pro. Free includes quarter and eighth notes.',
          ));
      return;
    }
    store.setMetronome(subIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, metro]),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _Hero(store: store, metro: metro),
            if (metro.notice != null) ...[
              const SizedBox(height: 12),
              Card(
                color: kOffCoral.withValues(alpha: 0.12),
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: kOffCoral),
                  title: Text(metro.notice!),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: metro.clearNotice,
                  ),
                ),
              ),
            ],
            SectionTitle(tr(zh: '拍号', en: 'Time signature')),
            ChoiceRow<int>(
              items: [for (var i = 0; i < kTimeSignatures.length; i++) i],
              selected: store.timeSignatureIndex,
              label: (i) => kTimeSignatures[i].label,
              onSelected: (i) => _pickSignature(context, i),
              isLocked: (i) => !kTimeSignatures[i].free && !store.pro,
              onLocked: (i) => _pickSignature(context, i),
            ),
            SectionTitle(tr(zh: '细分', en: 'Subdivision')),
            ChoiceRow<int>(
              items: [for (var i = 0; i < Subdivision.values.length; i++) i],
              selected: store.subdivisionIndex,
              label: (i) {
                final s = Subdivision.values[i];
                final name = switch (s) {
                  Subdivision.quarter => tr(zh: '四分', en: 'Quarter'),
                  Subdivision.eighth => tr(zh: '八分', en: 'Eighth'),
                  Subdivision.triplet => tr(zh: '三连音', en: 'Triplet'),
                  Subdivision.sixteenth => tr(zh: '十六分', en: 'Sixteenth'),
                };
                return '${s.glyph} $name';
              },
              onSelected: (i) => _pickSubdivision(context, i),
              isLocked: (i) => !Subdivision.values[i].free && !store.pro,
              onLocked: (i) => _pickSubdivision(context, i),
            ),
            SectionTitle(tr(zh: '常用速度', en: 'Presets')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in const [60, 80, 100, 120, 140, 160])
                  ActionChip(
                    label: Text('$p'),
                    onPressed: () => metro.setBpm(p),
                    backgroundColor: store.bpm == p ? cs.primary.withValues(alpha: 0.2) : null,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                zh: '节拍由音频引擎按采样精确排程,锁屏后继续走拍;来电时会自动停止。',
                en: 'Beats are scheduled sample-accurately by the audio engine and keep going with the screen locked; a phone call stops them.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.store, required this.metro});
  final TuneKitStore store;
  final MetronomeController metro;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sig = store.timeSignature;
    final onBeat = metro.playing && metro.currentBeat >= 0 && metro.currentKind != TickKind.sub;
    return Container(
      decoration: BoxDecoration(
        gradient: heroGradient(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: kWalnutEbony.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Beat ripples spread from the tempo figure, behind the controls.
            Positioned.fill(
              child: IgnorePointer(
                child: _BeatRipples(
                  serial: metro.tickSerial,
                  fire: onBeat,
                  accent: onBeat && sig.accents.contains(metro.currentBeat),
                  intervalMs: 60000 ~/ store.bpm,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                children: [
                  // Beat indicator.
                  SizedBox(
                    height: 44,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var b = 0; b < sig.beats; b++) ...[
                          _BeatDot(
                            accent: sig.accents.contains(b),
                            lit: metro.playing && metro.currentBeat == b,
                            serial: metro.tickSerial,
                          ),
                          if (b < sig.beats - 1) const SizedBox(width: 12),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${store.bpm}',
                    style: text.displayLarge?.copyWith(color: Colors.white, fontSize: 96, height: 1),
                  ),
                  Text(
                    'BPM · ${tempoMarking(store.bpm)}',
                    style: text.labelLarge?.copyWith(color: Colors.white70, letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _RoundIcon(
                        icon: Icons.remove,
                        label: tr(zh: '减慢 1 BPM,长按减 10', en: 'Slower by 1 BPM, hold for 10'),
                        onTap: () => metro.nudge(-1),
                        onLong: () => metro.nudge(-10),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: kBeatAmber,
                            thumbColor: kBeatAmber,
                            inactiveTrackColor: Colors.white24,
                            overlayColor: kBeatAmber.withValues(alpha: 0.15),
                          ),
                          child: Slider(
                            value: store.bpm.toDouble(),
                            min: kMinBpm.toDouble(),
                            max: kMaxBpm.toDouble(),
                            label: tr(zh: '速度', en: 'Tempo'),
                            semanticFormatterCallback: (v) => '${v.round()} BPM',
                            onChanged: (v) => metro.setBpm(v.round()),
                          ),
                        ),
                      ),
                      _RoundIcon(
                        icon: Icons.add,
                        label: tr(zh: '加快 1 BPM,长按加 10', en: 'Faster by 1 BPM, hold for 10'),
                        onTap: () => metro.nudge(1),
                        onLong: () => metro.nudge(10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Tap | play | metre. The side cells flex so the row fits a
                  // 360 dp screen (288 dp usable here) instead of a fixed 308.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: PressScale(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white38),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: metro.tap,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(tr(zh: '打拍', en: 'Tap'), maxLines: 1, softWrap: false),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PlayButton(playing: metro.playing, onTap: metro.toggle),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${sig.label} · ${store.subdivision.glyph}',
                                maxLines: 1,
                                softWrap: false,
                                style: text.titleMedium?.copyWith(color: Colors.white70),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One expanding, fading ring per beat, launched from the centre of the pad
/// on the same delayed tick the dots use (so it lands with the click). The
/// accented beat gets a larger, amber ring; subdivisions get none. A ring
/// lives for most of one beat interval, so at fast tempi they chase each
/// other outwards. Off under reduced motion.
class _BeatRipples extends StatefulWidget {
  const _BeatRipples({
    required this.serial,
    required this.fire,
    required this.accent,
    required this.intervalMs,
  });

  final int serial;
  final bool fire;
  final bool accent;
  final int intervalMs;

  @override
  State<_BeatRipples> createState() => _BeatRipplesState();
}

class _Ripple {
  _Ripple(this.controller, this.accent);
  final AnimationController controller;
  final bool accent;
}

class _BeatRipplesState extends State<_BeatRipples> with TickerProviderStateMixin {
  /// Rings alive at once. A ring lasts ≤ 0.9 beat, so more than two or
  /// three means the tab was hidden with tickers muted; cap it so a long
  /// run cannot pile up controllers.
  static const int _maxLive = 4;

  final List<_Ripple> _live = [];

  @override
  void didUpdateWidget(_BeatRipples old) {
    super.didUpdateWidget(old);
    if (widget.serial != old.serial && widget.fire && motionEnabled(context)) _spawn();
  }

  void _spawn() {
    // Hidden tab (IndexedStack + TickerMode off): a new controller would
    // never tick, so its completion could never retire it.
    if (!TickerMode.valuesOf(context).enabled) return;
    if (_live.length >= _maxLive) {
      _live.removeAt(0).controller.dispose();
    }
    final ms = (widget.intervalMs * 0.9).round().clamp(280, 720);
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: ms));
    final r = _Ripple(c, widget.accent);
    _live.add(r);
    c.addListener(() => setState(() {}));
    // Retire on natural completion. The TickerFuture never completes when
    // the controller is disposed early (cap above / dispose()), so this
    // cannot double-dispose; and it runs outside the controller's own
    // status callback, so disposing here is safe.
    c.forward().whenComplete(() {
      if (!mounted || !_live.remove(r)) return;
      c.dispose();
      setState(() {});
    });
  }

  @override
  void dispose() {
    for (final r in _live) {
      r.controller.dispose();
    }
    _live.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_live.isEmpty) return const SizedBox.expand();
    return CustomPaint(
      painter: _RipplePainter([
        for (final r in _live) (t: r.controller.value, accent: r.accent),
      ]),
      size: Size.infinite,
    );
  }
}

class _RipplePainter extends CustomPainter {
  const _RipplePainter(this.ripples);
  final List<({double t, bool accent})> ripples;

  @override
  void paint(Canvas canvas, Size size) {
    // Centred on the tempo figure (upper-middle of the pad).
    final center = Offset(size.width / 2, size.height * 0.40);
    final maxR = size.width * 0.62;
    for (final r in ripples) {
      final e = Curves.easeOutCubic.transform(r.t);
      final radius = 22 + (r.accent ? maxR : maxR * 0.66) * e;
      final fade = (1 - r.t);
      final color = r.accent ? kBeatAmber : Colors.white;
      if (r.accent) {
        canvas.drawCircle(center, radius, Paint()..color = color.withValues(alpha: 0.10 * fade));
      }
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (r.accent ? 6 : 4) * (1 - 0.6 * e) + 1
          ..color = color.withValues(alpha: (r.accent ? 0.55 : 0.38) * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => true;
}

class _BeatDot extends StatelessWidget {
  const _BeatDot({required this.accent, required this.lit, required this.serial});
  final bool accent;
  final bool lit;
  final int serial;

  @override
  Widget build(BuildContext context) {
    final size = accent ? 26.0 : 18.0;
    return AnimatedContainer(
      key: ValueKey(lit ? serial : -1),
      duration: motionEnabled(context) ? Duration(milliseconds: lit ? 30 : 180) : Duration.zero,
      width: lit ? size + 8 : size,
      height: lit ? size + 8 : size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: lit
            ? (accent ? kBeatAmber : Colors.white)
            : Colors.white.withValues(alpha: accent ? 0.35 : 0.22),
        boxShadow: lit
            ? [BoxShadow(color: (accent ? kBeatAmber : Colors.white).withValues(alpha: 0.6), blurRadius: 14)]
            : null,
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.label, required this.onTap, required this.onLong});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onLong;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: PressScale(
        pressedScale: 0.9,
        child: Material(
          color: Colors.white.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            onLongPress: onLong,
            child: SizedBox(
              width: 40,
              height: 40,
              child: ExcludeSemantics(child: Icon(icon, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Start/stop: sinks under the finger, the colour cross-fades amber↔coral
/// and the glyph swaps with a scale-fade — the state change is visible even
/// before the first click sounds.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onTap});
  final bool playing;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final color = playing ? kOffCoral : kBeatAmber;
    return Semantics(
      button: true,
      label: playing ? tr(zh: '停止', en: 'Stop') : tr(zh: '开始', en: 'Start'),
      child: PressScale(
        pressedScale: 0.9,
        child: AnimatedContainer(
          duration: motionEnabled(context) ? kMotionMedium : Duration.zero,
          curve: Curves.easeOutCubic,
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SwapFade(
                duration: kMotionShort,
                child: Icon(
                  playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(playing),
                  size: 42,
                  color: kOnAmber,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
