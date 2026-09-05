import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'audio_bridge.dart';
import 'mic_controller.dart';
import 'music/theory.dart';
import 'music/tunings.dart';
import 'painters.dart';
import 'pitch/pitch_tracker.dart';
import 'pro.dart';
import 'store.dart';
import 'ui_common.dart';

/// The tuner tab. Starts the microphone whenever the tab is visible and
/// permission is granted; stops it when the tab is hidden.
class TunerPage extends StatefulWidget {
  const TunerPage({super.key, required this.store, required this.mic, required this.active});

  final TuneKitStore store;
  final MicPitchController mic;
  final bool active;

  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
  /// Manually selected string index (null = auto-detect nearest).
  int? _manualString;

  @override
  void initState() {
    super.initState();
    widget.mic.refreshPermission().then((_) => _syncRunning());
  }

  @override
  void didUpdateWidget(TunerPage old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncRunning();
  }

  void _syncRunning() {
    if (!mounted) return;
    final mic = widget.mic;
    if (widget.active) {
      if (mic.permission == MicPermission.granted && !mic.running) {
        mic.start(attributeTo: PracticeTool.tuner);
      }
    } else if (mic.running) {
      mic.stop();
    }
  }

  Future<void> _allow() async {
    await widget.mic.start(attributeTo: PracticeTool.tuner);
  }

  void _pickInstrument(String id) {
    final inst = instrumentById(id);
    if (!inst.free && !widget.store.pro) {
      showProSheet(context,
          reason: tr(
            zh: '${inst.nameZh}预设(每根弦一个按钮)是 Pro 功能。免费版的半音模式同样能给任何乐器调音。',
            en: '${inst.nameEn} preset (a button per string) is a Pro feature. Chromatic mode, free, tunes any instrument too.',
          ));
      return;
    }
    setState(() => _manualString = null);
    widget.store.setInstrument(id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.store, widget.mic]),
      builder: (context, _) {
        final store = widget.store;
        final mic = widget.mic;
        final inst = instrumentById(store.instrumentId);
        final reading = mic.reading;

        // Target note: manual string, else nearest string, else nearest note.
        int? targetMidi;
        double? cents = reading.cents;
        if (reading.hasPitch) {
          final midiF = reading.midi! + (reading.cents ?? 0) / 100;
          if (!inst.isChromatic) {
            final idx = _manualString ?? inst.nearestString(midiF);
            targetMidi = inst.strings[idx];
            cents = ((midiF - targetMidi) * 100).clamp(-50.0, 50.0);
          } else {
            targetMidi = reading.midi;
          }
        } else if (_manualString != null && !inst.isChromatic) {
          targetMidi = inst.strings[_manualString!];
        }
        final inTune = reading.hasPitch && cents != null && cents.abs() <= PitchTracker.inTuneCents;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _Hero(
              reading: reading,
              cents: cents,
              targetMidi: targetMidi,
              inTune: inTune,
              running: mic.running,
              flats: false,
            ),
            const SizedBox(height: 12),
            if (mic.permission != MicPermission.granted)
              _PermissionCard(mic: mic, onAllow: _allow)
            else if (mic.error != null)
              _ErrorCard(message: mic.error!, onRetry: _allow)
            else
              _StatusLine(reading: reading, running: mic.running, starting: mic.starting),
            SectionTitle(tr(zh: '乐器', en: 'Instrument')),
            ChoiceRow<Instrument>(
              items: kInstruments,
              selected: inst,
              label: (i) => tr(zh: i.nameZh, en: i.nameEn),
              onSelected: (i) => _pickInstrument(i.id),
              isLocked: (i) => !i.free && !store.pro,
              onLocked: (i) => _pickInstrument(i.id),
            ),
            if (!inst.isChromatic) ...[
              SectionTitle(
                tr(zh: '弦(点选固定目标,再点取消)', en: 'Strings (tap to pin a target, tap again to release)'),
              ),
              _StringButtons(
                inst: inst,
                manual: _manualString,
                detected: reading.hasPitch && _manualString == null
                    ? inst.nearestString(reading.midi! + (reading.cents ?? 0) / 100)
                    : null,
                inTune: inTune,
                onTap: (i) => setState(() => _manualString = _manualString == i ? null : i),
              ),
            ],
            SectionTitle(tr(zh: '标准音', en: 'Reference pitch')),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('A4 = ${store.a4.round()} Hz',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                            tr(zh: '默认 440,管弦乐常用 442', en: '440 is standard; orchestras often use 442'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: store.a4 > 430 ? () => _setA4(store.a4 - 1) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      onPressed: store.a4 < 450 ? () => _setA4(store.a4 + 1) : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _setA4(double v) {
    widget.store.setA4(v);
    widget.mic.setA4(v);
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.reading,
    required this.cents,
    required this.targetMidi,
    required this.inTune,
    required this.running,
    required this.flats,
  });

  final TunerReading reading;
  final double? cents;
  final int? targetMidi;
  final bool inTune;
  final bool running;
  final bool flats;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final active = reading.hasPitch;
    final name = targetMidi == null
        ? '—'
        : pitchClassName(pitchClassOf(targetMidi!), flats: flats);
    final octave = targetMidi == null ? '' : octaveOf(targetMidi!).toString();
    final centsText = active && cents != null
        ? '${cents! >= 0 ? '+' : '−'}${cents!.abs().toStringAsFixed(0)}¢'
        : '';
    final hz = reading.frequency == null ? '' : '${reading.frequency!.toStringAsFixed(1)} Hz';
    final accent = !active ? cs.onSurface.withValues(alpha: 0.5) : (inTune ? kInTuneGreen : kOffCoral);

    return Container(
      decoration: BoxDecoration(
        gradient: heroGradient(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Column(
        children: [
          SizedBox(
            height: 210,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: TunerGaugePainter(
                      cents: active ? cents : null,
                      active: active,
                      inTune: inTune,
                      scheme: cs.copyWith(onSurface: Colors.white),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 34,
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                              style: text.displayLarge?.copyWith(
                                  color: active ? Colors.white : Colors.white54, fontSize: 64)),
                          Text(octave,
                              style: text.headlineSmall?.copyWith(color: Colors.white70)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 84,
                child: Text(centsText,
                    textAlign: TextAlign.right,
                    style: text.titleLarge?.copyWith(color: accent, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  !running
                      ? tr(zh: '未开始', en: 'Idle')
                      : !active
                          ? tr(zh: '等待声音', en: 'Listening')
                          : inTune
                              ? tr(zh: '准了', en: 'In tune')
                              : (cents! < 0 ? tr(zh: '偏低 ↑', en: 'Flat ↑') : tr(zh: '偏高 ↓', en: 'Sharp ↓')),
                  style: text.labelLarge?.copyWith(color: active ? accent : Colors.white70),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 84,
                child: Text(hz,
                    style: text.bodyMedium?.copyWith(color: Colors.white70, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Input level meter.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: reading.level.clamp(0, 1),
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              color: reading.level > 0.05 ? kInTuneGreen.withValues(alpha: 0.8) : Colors.white24,
            ),
          ),
        ],
      ),
    );
  }
}

class _StringButtons extends StatelessWidget {
  const _StringButtons({
    required this.inst,
    required this.manual,
    required this.detected,
    required this.inTune,
    required this.onTap,
  });

  final Instrument inst;
  final int? manual;
  final int? detected;
  final bool inTune;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < inst.strings.length; i++) ...[
          Expanded(
            child: _StringButton(
              label: stringLabel(inst.strings[i]),
              pinned: manual == i,
              lit: detected == i || manual == i,
              litColor: (detected == i || manual == i) && inTune ? kInTuneGreen : cs.primary,
              onTap: () => onTap(i),
            ),
          ),
          if (i < inst.strings.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _StringButton extends StatelessWidget {
  const _StringButton({
    required this.label,
    required this.pinned,
    required this.lit,
    required this.litColor,
    required this.onTap,
  });

  final String label;
  final bool pinned;
  final bool lit;
  final Color litColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: lit ? litColor.withValues(alpha: 0.22) : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: pinned ? litColor : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: lit ? litColor : cs.onSurface,
                        fontWeight: FontWeight.w700,
                      )),
              if (pinned)
                Icon(Icons.push_pin, size: 12, color: litColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.mic, required this.onAllow});
  final MicPitchController mic;
  final Future<void> Function() onAllow;

  @override
  Widget build(BuildContext context) {
    final permanent = mic.permission == MicPermission.permanentlyDenied;
    return GuidanceCard(
      icon: Icons.mic_none,
      tint: permanent ? kOffCoral : null,
      title: permanent
          ? tr(zh: '麦克风权限已关闭', en: 'Microphone access is off')
          : tr(zh: '让调音器听到你的乐器', en: 'Let the tuner hear your instrument'),
      body: permanent
          ? tr(
              zh: '系统设置里本应用的麦克风开关是关的。打开后回来,调音器会自动开始。声音只在本机分析,不录音不上传。',
              en: 'This app\'s microphone switch is off in system settings. Turn it on and come back; the tuner starts by itself. Audio is analysed on the device only, never recorded or uploaded.',
            )
          : tr(
              zh: '调音需要使用麦克风。声音只在本机即时分析,不会录音,也不会上传。',
              en: 'Tuning needs the microphone. Audio is analysed on the device in real time — never recorded, never uploaded.',
            ),
      action: FilledButton.icon(
        onPressed: permanent ? mic.openSettings : onAllow,
        icon: Icon(permanent ? Icons.settings : Icons.mic),
        label: Text(permanent
            ? tr(zh: '去系统设置', en: 'Open system settings')
            : tr(zh: '允许麦克风', en: 'Allow microphone')),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return GuidanceCard(
      icon: Icons.mic_off,
      tint: kOffCoral,
      title: tr(zh: '麦克风没有在听', en: 'The microphone is not listening'),
      body: message,
      action: FilledButton.tonalIcon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: Text(tr(zh: '开始', en: 'Start')),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.reading, required this.running, required this.starting});
  final TunerReading reading;
  final bool running;
  final bool starting;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final String msg;
    if (starting) {
      msg = tr(zh: '正在打开麦克风…', en: 'Opening the microphone…');
    } else if (!running) {
      msg = tr(zh: '切回本页会自动开始。', en: 'Starts automatically when this tab is shown.');
    } else if (reading.state == SignalState.quiet) {
      msg = tr(zh: '声音太小了,靠近一点或弹重一些。', en: 'Too quiet — move closer or play a little louder.');
    } else if (!reading.hasPitch) {
      msg = tr(zh: '弹一根弦,让它响一会儿。', en: 'Play one string and let it ring.');
    } else {
      msg = reading.inTune
          ? tr(zh: '保持住,这根弦准了。', en: 'Hold it — this string is in tune.')
          : (reading.cents! < 0
              ? tr(zh: '拧紧一点,音要高一些。', en: 'Tighten slightly — the note needs to go up.')
              : tr(zh: '放松一点,音要低一些。', en: 'Loosen slightly — the note needs to come down.'));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
