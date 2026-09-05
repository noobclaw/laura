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
    return Container(
      decoration: BoxDecoration(
        gradient: heroGradient(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(28),
      ),
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
              _RoundIcon(icon: Icons.remove, onTap: () => metro.nudge(-1), onLong: () => metro.nudge(-10)),
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
                    onChanged: (v) => metro.setBpm(v.round()),
                  ),
                ),
              ),
              _RoundIcon(icon: Icons.add, onTap: () => metro.nudge(1), onLong: () => metro.nudge(10)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 96,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: metro.tap,
                  child: Text(tr(zh: '打拍', en: 'Tap')),
                ),
              ),
              const SizedBox(width: 20),
              _PlayButton(playing: metro.playing, onTap: metro.toggle),
              const SizedBox(width: 20),
              SizedBox(
                width: 96,
                height: 48,
                child: Center(
                  child: Text(
                    '${sig.label} · ${store.subdivision.glyph}',
                    style: text.titleMedium?.copyWith(color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
      duration: Duration(milliseconds: lit ? 30 : 180),
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
  const _RoundIcon({required this.icon, required this.onTap, required this.onLong});
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLong;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        onLongPress: onLong,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onTap});
  final bool playing;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? tr(zh: '停止', en: 'Stop') : tr(zh: '开始', en: 'Start'),
      child: Material(
        color: playing ? kOffCoral : kBeatAmber,
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: (playing ? kOffCoral : kBeatAmber).withValues(alpha: 0.5),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 76,
            height: 76,
            child: Icon(
              playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 42,
              color: const Color(0xFF1B1200),
            ),
          ),
        ),
      ),
    );
  }
}
