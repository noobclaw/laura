import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'audio_bridge.dart';
import 'mic_controller.dart';
import 'music/theory.dart';
import 'music/tunings.dart';
import 'music/voicing.dart';
import 'painters.dart';
import 'pitch/pitch_tracker.dart';
import 'pro.dart';
import 'store.dart';
import 'ui_common.dart';

/// Instruments offered for diagrams and checks. `piano` is a keyboard with
/// no strings; the fretted ones reuse the tuner presets.
const List<String> kPracticeInstruments = ['guitar', 'ukulele', 'piano'];

String practiceInstrumentName(String id) => switch (id) {
      'guitar' => tr(zh: '吉他', en: 'Guitar'),
      'ukulele' => tr(zh: '尤克里里', en: 'Ukulele'),
      _ => tr(zh: '键盘', en: 'Keyboard'),
    };

bool patternAllowed(TuneKitStore store, IntervalPattern p) => p.free || store.pro;

String groupName(PatternGroup g) => switch (g) {
      PatternGroup.triads => tr(zh: '三和弦', en: 'Triads'),
      PatternGroup.sevenths => tr(zh: '七和弦与六和弦', en: 'Sevenths & sixths'),
      PatternGroup.extended => tr(zh: '扩展和弦', en: 'Extended chords'),
      PatternGroup.suspended => tr(zh: '挂留和弦', en: 'Suspended chords'),
      PatternGroup.scalesBasic => tr(zh: '基础音阶', en: 'Basic scales'),
      PatternGroup.scalesPentatonic => tr(zh: '五声与布鲁斯', en: 'Pentatonic & blues'),
      PatternGroup.scalesModes => tr(zh: '调式', en: 'Modes'),
      PatternGroup.scalesExotic => tr(zh: '其它音阶', en: 'Other scales'),
    };

class PracticePage extends StatefulWidget {
  const PracticePage({super.key, required this.store, required this.mic});
  final TuneKitStore store;
  final MicPitchController mic;

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  int _root = 0;
  bool _chords = true;

  void _open(IntervalPattern p) {
    if (!patternAllowed(widget.store, p)) {
      showProSheet(context,
          reason: tr(
            zh: '免费版包含 5 种类型:大三、小三、属七和弦,大调与小调五声音阶。完整字典是 Pro 功能。',
            en: 'Free includes five types: major, minor and dominant 7th chords, the major scale and the minor pentatonic. The full dictionary is Pro.',
          ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PatternDetailPage(
        store: widget.store,
        mic: widget.mic,
        item: RootedPattern(_root, p),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final cs = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;
        final items = _chords ? kChordTypes : kScaleTypes;
        final groups = <PatternGroup, List<IntervalPattern>>{};
        for (final p in items) {
          groups.putIfAbsent(p.group, () => []).add(p);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Hero: drill entry.
            Container(
              decoration: BoxDecoration(
                gradient: heroGradient(Theme.of(context).brightness),
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(zh: '随机训练', en: 'Random drill'),
                            style: text.titleLarge?.copyWith(color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(
                          store.drillBest > 0
                              ? tr(zh: '最佳成绩 ${store.drillBest} 分 · 10 题一轮', en: 'Best ${store.drillBest} pts · 10 questions a round')
                              : tr(zh: '10 题一轮,认音、认和弦、认音阶', en: '10 questions: name the notes, the chord, the scale'),
                          style: text.bodyMedium?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kBeatAmber, foregroundColor: const Color(0xFF1B1200)),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DrillPage(store: store),
                    )),
                    icon: const Icon(Icons.bolt),
                    label: Text(tr(zh: '开始', en: 'Start')),
                  ),
                ],
              ),
            ),
            SectionTitle(tr(zh: '根音', en: 'Root')),
            ChoiceRow<int>(
              items: [for (var i = 0; i < 12; i++) i],
              selected: _root,
              label: (i) => pitchClassName(i, flats: kFlatRoots.contains(i)),
              onSelected: (i) => setState(() => _root = i),
            ),
            SectionTitle(tr(zh: '乐器图示', en: 'Diagram')),
            ChoiceRow<String>(
              items: kPracticeInstruments,
              selected: store.practiceInstrumentId,
              label: practiceInstrumentName,
              onSelected: store.setPracticeInstrument,
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(tr(zh: '和弦', en: 'Chords')), icon: const Icon(Icons.queue_music)),
                ButtonSegment(value: false, label: Text(tr(zh: '音阶', en: 'Scales')), icon: const Icon(Icons.stairs_outlined)),
              ],
              selected: {_chords},
              onSelectionChanged: (s) => setState(() => _chords = s.first),
            ),
            for (final e in groups.entries) ...[
              SectionTitle(groupName(e.key)),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < e.value.length; i++) ...[
                      _PatternTile(
                        item: RootedPattern(_root, e.value[i]),
                        locked: !patternAllowed(store, e.value[i]),
                        onTap: () => _open(e.value[i]),
                      ),
                      if (i < e.value.length - 1)
                        Divider(indent: 16, endIndent: 16, color: cs.outlineVariant.withValues(alpha: 0.4)),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PatternTile extends StatelessWidget {
  const _PatternTile({required this.item, required this.locked, required this.onTap});
  final RootedPattern item;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      title: Row(
        children: [
          Text(item.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(zh: item.pattern.nameZh, en: item.pattern.nameEn),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(item.noteNames.join('  '),
          style: TextStyle(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
      trailing: locked ? const ProBadge() : Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
    );
  }
}

// ---------------------------------------------------------------- detail

class PatternDetailPage extends StatelessWidget {
  const PatternDetailPage({super.key, required this.store, required this.mic, required this.item});
  final TuneKitStore store;
  final MicPitchController mic;
  final RootedPattern item;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;
        final instId = store.practiceInstrumentId;
        final inst = instId == 'piano' ? null : instrumentById(instId);
        final voicing = inst != null && item.pattern.isChord ? deriveVoicing(item, inst) : null;
        final pcs = item.pitchClasses.toSet();

        return Scaffold(
          appBar: AppBar(title: Text(item.label)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              Text(tr(zh: item.pattern.nameZh, en: item.pattern.nameEn),
                  style: text.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < item.pattern.semitones.length; i++)
                    _NoteChip(
                      name: pitchClassName((item.root + item.pattern.semitones[i]) % 12, flats: item.useFlats),
                      degree: item.pattern.isChord
                          ? degreeLabel(item.pattern.semitones[i])
                          : scaleDegreeLabel(item.pattern.semitones[i]),
                      root: i == 0,
                    ),
                ],
              ),
              SectionTitle(
                inst == null
                    ? tr(zh: '键盘', en: 'Keyboard')
                    : (voicing != null
                        ? tr(zh: '建议指法(自动推导)· ${voicing.shorthand}', en: 'Suggested shape (auto-derived) · ${voicing.shorthand}')
                        : tr(zh: '指板上的音', en: 'On the fretboard')),
                trailing: ChoiceRow<String>(
                  items: kPracticeInstruments,
                  selected: instId,
                  label: practiceInstrumentName,
                  onSelected: store.setPracticeInstrument,
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    height: inst == null ? 150 : 40.0 * (inst.strings.length - 1) + 60,
                    child: CustomPaint(
                      painter: inst == null
                          ? PianoPainter(
                              highlightMidi: item.midiNotes(baseMidi: 48).toSet(),
                              root: item.root,
                              scheme: cs,
                              flats: item.useFlats,
                            )
                          : FretboardPainter(
                              strings: inst.strings,
                              scheme: cs,
                              frets: voicing != null ? 5 : 12,
                              highlight: pcs,
                              root: item.root,
                              voicing: voicing?.frets,
                              flats: item.useFlats,
                            ),
                    ),
                  ),
                ),
              ),
              if (voicing != null) ...[
                const SizedBox(height: 8),
                Text(
                  tr(
                    zh: '指法按「根音在最低弦、每弦取最低品」自动推导,常见开放和弦与教材一致;× 为不弹的弦,○ 为空弦。',
                    en: 'Shape derived automatically (root on the lowest string, lowest fret per string); common open chords match the textbook. × = do not play, ○ = open string.',
                  ),
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                ),
                if (_omitted(item, voicing).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    tr(
                      zh: '这个指法省略了 ${_omitted(item, voicing).join('、')}(弹奏检查只查实际按出的音)。',
                      en: 'This shape leaves out ${_omitted(item, voicing).join(', ')} (play-and-check only tests the notes it fingers).',
                    ),
                    style: text.bodySmall?.copyWith(color: kBeatAmber, height: 1.4),
                  ),
                ],
              ],
              if (inst != null && voicing == null) ...[
                SectionTitle(tr(zh: '键盘', en: 'Keyboard')),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      height: 130,
                      child: CustomPaint(
                        painter: PianoPainter(
                          highlightMidi: item.midiNotes(baseMidi: 48).toSet(),
                          root: item.root,
                          scheme: cs,
                          flats: item.useFlats,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CheckPage(store: store, mic: mic, item: item, instrument: inst, voicing: voicing),
                )),
                icon: const Icon(Icons.mic),
                label: Text(item.pattern.isChord
                    ? tr(zh: '弹奏检查:弹这个和弦,我来听', en: 'Play and check: play the chord, I listen')
                    : tr(zh: '弹奏检查:上行弹一遍音阶', en: 'Play and check: play the scale ascending')),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Chord tones the derived shape does not finger (the fifth is a normal
/// omission and is not reported).
List<String> _omitted(RootedPattern item, Voicing v) {
  final sounded = v.soundedPitchClasses;
  return [
    for (final pc in item.pitchClasses)
      if (!sounded.contains(pc) && pc != (item.root + 7) % 12)
        pitchClassName(pc, flats: item.useFlats),
  ];
}

class _NoteChip extends StatelessWidget {
  const _NoteChip({required this.name, required this.degree, required this.root});
  final String name;
  final String degree;
  final bool root;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: root ? kBeatAmber.withValues(alpha: 0.2) : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: root ? kBeatAmber : Colors.transparent),
      ),
      child: Column(
        children: [
          Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(degree, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- check

class _Target {
  _Target({required this.label, this.midi, required this.pitchClass});
  final String label;

  /// Exact expected MIDI (string mode) or null (pitch-class mode).
  final int? midi;
  final int pitchClass;
  double? cents;
  bool get done => cents != null;
}

/// "Play it and I check" — per string for a fretted chord voicing, by
/// pitch class for keyboard chords, in order for scales.
class CheckPage extends StatefulWidget {
  const CheckPage({
    super.key,
    required this.store,
    required this.mic,
    required this.item,
    required this.instrument,
    required this.voicing,
  });

  final TuneKitStore store;
  final MicPitchController mic;
  final RootedPattern item;
  final Instrument? instrument;
  final Voicing? voicing;

  @override
  State<CheckPage> createState() => _CheckPageState();
}

class _CheckPageState extends State<CheckPage> {
  late List<_Target> _targets;
  StreamSubscription<TunerReading>? _sub;
  int? _lastMatchedMidi;
  bool _passed = false;
  int _nextScaleIndex = 0;

  bool get _stringMode => widget.voicing != null;
  bool get _scaleMode => !widget.item.pattern.isChord;

  @override
  void initState() {
    super.initState();
    _reset();
    _sub = widget.mic.readings.listen(_onReading);
    widget.mic.start(attributeTo: PracticeTool.practice);
  }

  void _reset() {
    final item = widget.item;
    final v = widget.voicing;
    if (v != null) {
      _targets = [
        for (var s = 0; s < v.frets.length; s++)
          if (v.frets[s] >= 0)
            _Target(
              label: noteName(v.midiAt(s)!, flats: item.useFlats),
              midi: v.midiAt(s),
              pitchClass: pitchClassOf(v.midiAt(s)!),
            ),
      ];
    } else {
      _targets = [
        for (final pc in item.pitchClasses)
          _Target(label: pitchClassName(pc, flats: item.useFlats), pitchClass: pc),
      ];
      if (_scaleMode) {
        // The octave completes an ascending scale.
        _targets.add(_Target(label: pitchClassName(item.root, flats: item.useFlats), pitchClass: item.root));
      }
    }
    _lastMatchedMidi = null;
    _passed = false;
    _nextScaleIndex = 0;
  }

  void _onReading(TunerReading r) {
    if (_passed || !mounted) return;
    if (!r.stable || !r.hasPitch || r.cents == null) {
      if (!r.hasPitch) _lastMatchedMidi = null; // note released: allow a repeat
      return;
    }
    final midi = r.midi!;
    if (midi == _lastMatchedMidi) return;
    final pc = pitchClassOf(midi);
    _Target? hit;
    if (_scaleMode) {
      if (_nextScaleIndex < _targets.length && _targets[_nextScaleIndex].pitchClass == pc) {
        hit = _targets[_nextScaleIndex];
        _nextScaleIndex++;
      }
    } else if (_stringMode) {
      final open = _targets.where((t) => !t.done && t.pitchClass == pc).toList();
      if (open.isNotEmpty) {
        open.sort((a, b) => (a.midi! - midi).abs().compareTo((b.midi! - midi).abs()));
        if ((open.first.midi! - midi).abs() <= 12) hit = open.first;
      }
    } else {
      for (final t in _targets) {
        if (!t.done && t.pitchClass == pc) {
          hit = t;
          break;
        }
      }
    }
    if (hit == null) return;
    _lastMatchedMidi = midi;
    setState(() {
      hit!.cents = r.cents;
      if (_targets.every((t) => t.done)) {
        _passed = true;
        widget.store.addCheckPassed();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.mic.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final done = _targets.where((t) => t.done).length;
    final meanAbs = done == 0
        ? null
        : _targets.where((t) => t.done).fold(0.0, (a, t) => a + t.cents!.abs()) / done;

    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '弹奏检查 · ${item.label}', en: 'Play & check · ${item.label}'))),
      body: ListenableBuilder(
        listenable: widget.mic,
        builder: (context, _) {
          final mic = widget.mic;
          final r = mic.reading;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              if (mic.permission != MicPermission.granted)
                GuidanceCard(
                  icon: Icons.mic_none,
                  title: tr(zh: '需要麦克风', en: 'Microphone needed'),
                  body: mic.permission == MicPermission.permanentlyDenied
                      ? tr(zh: '请到系统设置里为本应用打开麦克风。', en: 'Turn on the microphone for this app in system settings.')
                      : tr(zh: '检查你弹的音需要用麦克风,声音只在本机分析。', en: 'Checking what you play needs the microphone; audio stays on the device.'),
                  action: FilledButton(
                    onPressed: mic.permission == MicPermission.permanentlyDenied
                        ? mic.openSettings
                        : () => mic.start(attributeTo: PracticeTool.practice),
                    child: Text(mic.permission == MicPermission.permanentlyDenied
                        ? tr(zh: '去系统设置', en: 'Open settings')
                        : tr(zh: '允许麦克风', en: 'Allow microphone')),
                  ),
                )
              else if (mic.error != null)
                GuidanceCard(
                  icon: Icons.mic_off,
                  tint: kOffCoral,
                  title: tr(zh: '麦克风没有在听', en: 'The microphone is not listening'),
                  body: mic.error!,
                  action: FilledButton.tonal(
                    onPressed: () => mic.start(attributeTo: PracticeTool.practice),
                    child: Text(tr(zh: '重试', en: 'Retry')),
                  ),
                ),
              // Live reading.
              Container(
                decoration: BoxDecoration(
                  gradient: heroGradient(Theme.of(context).brightness),
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _passed
                                ? tr(zh: '全部对了!', en: 'All correct!')
                                : _scaleMode
                                    ? tr(zh: '下一个音:${_nextScaleIndex < _targets.length ? _targets[_nextScaleIndex].label : '—'}', en: 'Next note: ${_nextScaleIndex < _targets.length ? _targets[_nextScaleIndex].label : '—'}')
                                    : _stringMode
                                        ? tr(zh: '从低到高逐根弦弹,让每个音响清楚', en: 'Pluck each string low to high and let it ring')
                                        : tr(zh: '逐个弹出和弦里的每个音', en: 'Play each chord tone one at a time'),
                            style: text.titleMedium?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text('$done / ${_targets.length}',
                              style: text.bodyMedium?.copyWith(color: Colors.white70)),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          r.hasPitch ? noteName(r.midi!, flats: item.useFlats) : '—',
                          style: text.headlineMedium?.copyWith(
                              color: r.hasPitch ? (r.inTune ? kInTuneGreen : Colors.white) : Colors.white38),
                        ),
                        Text(
                          r.hasPitch && r.cents != null ? '${r.cents! >= 0 ? '+' : '−'}${r.cents!.abs().round()}¢' : '',
                          style: text.labelLarge?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_stringMode && widget.instrument != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      height: 40.0 * (widget.instrument!.strings.length - 1) + 60,
                      child: CustomPaint(
                        painter: FretboardPainter(
                          strings: widget.instrument!.strings,
                          scheme: cs,
                          frets: 5,
                          voicing: widget.voicing!.frets,
                          flats: item.useFlats,
                          stringStatus: [
                            for (var s = 0; s < widget.voicing!.frets.length; s++)
                              widget.voicing!.frets[s] < 0
                                  ? null
                                  : _statusForMidi(widget.voicing!.midiAt(s)!),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final t in _targets)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          t.done ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: t.done ? (t.cents!.abs() <= PitchTracker.inTuneCents ? kInTuneGreen : kBeatAmber) : cs.onSurfaceVariant,
                        ),
                        title: Text(t.label),
                        trailing: Text(
                          t.done ? '${t.cents! >= 0 ? '+' : '−'}${t.cents!.abs().round()}¢' : '',
                          style: text.labelLarge?.copyWith(
                              color: t.done && t.cents!.abs() <= PitchTracker.inTuneCents ? kInTuneGreen : kBeatAmber),
                        ),
                      ),
                  ],
                ),
              ),
              if (_passed) ...[
                const SizedBox(height: 16),
                GuidanceCard(
                  icon: Icons.emoji_events,
                  tint: kInTuneGreen,
                  title: tr(zh: '通过 · 平均偏差 ${meanAbs!.toStringAsFixed(1)}¢', en: 'Passed · mean deviation ${meanAbs.toStringAsFixed(1)}¢'),
                  body: meanAbs <= PitchTracker.inTuneCents
                      ? tr(zh: '每个音都在 ±5 音分以内,琴也调得很准。', en: 'Every note within ±5 cents — the instrument is well tuned too.')
                      : tr(zh: '音都对了,但有几根弦偏了一些,去调音页再校一下。', en: 'The notes are right, but a few were off — a quick visit to the tuner will help.'),
                  action: FilledButton.tonal(
                    onPressed: () => setState(_reset),
                    child: Text(tr(zh: '再来一次', en: 'Again')),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  bool? _statusForMidi(int midi) {
    for (final t in _targets) {
      if (t.midi == midi && t.done) return t.cents!.abs() <= 15;
    }
    return null;
  }
}

// ----------------------------------------------------------------- drill

class _Question {
  _Question({required this.prompt, required this.options, required this.answer, required this.subject});
  final String prompt;
  final List<String> options;
  final int answer;
  final RootedPattern subject;
}

class DrillPage extends StatefulWidget {
  const DrillPage({super.key, required this.store});
  final TuneKitStore store;

  static const int rounds = 10;

  @override
  State<DrillPage> createState() => _DrillPageState();
}

class _DrillPageState extends State<DrillPage> {
  final math.Random _rng = math.Random();
  late List<_Question> _questions;
  int _index = 0;
  int _score = 0;
  int _streak = 0;
  int _correct = 0;
  int? _chosen;
  Timer? _advance;

  List<IntervalPattern> get _pool =>
      kAllPatterns.where((p) => patternAllowed(widget.store, p)).toList();

  @override
  void initState() {
    super.initState();
    _questions = List.generate(DrillPage.rounds, (_) => _make());
  }

  @override
  void dispose() {
    _advance?.cancel();
    super.dispose();
  }

  _Question _make() {
    final pool = _pool;
    final pattern = pool[_rng.nextInt(pool.length)];
    final root = _rng.nextInt(12);
    final subject = RootedPattern(root, pattern);
    final kindWord = pattern.isChord ? tr(zh: '和弦', en: 'chord') : tr(zh: '音阶', en: 'scale');
    final notesToName = _rng.nextBool();
    if (notesToName) {
      // Given the notes, name it. Distractors: same root, other patterns of
      // the same kind, distinct note sets.
      final labels = <String>{subject.label};
      final options = [subject.label];
      final candidates = pool.where((p) => p.isChord == pattern.isChord && p.id != pattern.id).toList()..shuffle(_rng);
      for (final p in candidates) {
        final alt = RootedPattern(root, p);
        if (labels.add(alt.label) && alt.pitchClasses.toSet().difference(subject.pitchClasses.toSet()).isNotEmpty) {
          options.add(alt.label);
        }
        if (options.length == 4) break;
      }
      while (options.length < 4) {
        final alt = RootedPattern(_rng.nextInt(12), pattern);
        if (labels.add(alt.label)) options.add(alt.label);
      }
      options.shuffle(_rng);
      return _Question(
        prompt: tr(zh: '${subject.noteNames.join('  ')}\n是哪个$kindWord?', en: '${subject.noteNames.join('  ')}\nWhich $kindWord is this?'),
        options: options,
        answer: options.indexOf(subject.label),
        subject: subject,
      );
    }
    // Given the name, pick the notes.
    final correct = subject.noteNames.join('  ');
    final seen = <String>{correct};
    final options = [correct];
    final candidates = pool.where((p) => p.isChord == pattern.isChord && p.id != pattern.id).toList()..shuffle(_rng);
    for (final p in candidates) {
      final s = RootedPattern(root, p).noteNames.join('  ');
      if (seen.add(s)) options.add(s);
      if (options.length == 4) break;
    }
    while (options.length < 4) {
      final s = RootedPattern(_rng.nextInt(12), pattern).noteNames.join('  ');
      if (seen.add(s)) options.add(s);
    }
    options.shuffle(_rng);
    return _Question(
      prompt: tr(zh: '${subject.label}(${pattern.nameZh})\n包含哪些音?', en: '${subject.label} (${pattern.nameEn})\nWhich notes does it contain?'),
      options: options,
      answer: options.indexOf(correct),
      subject: subject,
    );
  }

  void _choose(int i) {
    if (_chosen != null) return;
    final q = _questions[_index];
    final ok = i == q.answer;
    setState(() {
      _chosen = i;
      if (ok) {
        _streak++;
        _correct++;
        _score += 10 + math.min(10, 2 * (_streak - 1));
      } else {
        _streak = 0;
      }
    });
    // The round's score only counts as a "best" once the round is complete.
    widget.store.addDrillAnswer(correct: ok, score: _index == DrillPage.rounds - 1 ? _score : 0);
    _advance = Timer(Duration(milliseconds: ok ? 700 : 1400), () {
      if (!mounted) return;
      setState(() {
        _index++;
        _chosen = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (_index >= DrillPage.rounds) {
      return Scaffold(
        appBar: AppBar(title: Text(tr(zh: '随机训练', en: 'Random drill'))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GuidanceCard(
              icon: Icons.emoji_events,
              tint: kBeatAmber,
              title: tr(zh: '$_score 分 · 答对 $_correct / ${DrillPage.rounds}', en: '$_score pts · $_correct / ${DrillPage.rounds} correct'),
              body: _score >= widget.store.drillBest && _score > 0
                  ? tr(zh: '新纪录!', en: 'New best!')
                  : tr(zh: '最佳成绩 ${widget.store.drillBest} 分', en: 'Best so far: ${widget.store.drillBest} pts'),
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr(zh: '返回', en: 'Back')),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => setState(() {
                      _questions = List.generate(DrillPage.rounds, (_) => _make());
                      _index = 0;
                      _score = 0;
                      _streak = 0;
                      _correct = 0;
                      _chosen = null;
                    }),
                    child: Text(tr(zh: '再来一轮', en: 'Another round')),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final q = _questions[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(zh: '第 ${_index + 1} / ${DrillPage.rounds} 题', en: 'Question ${_index + 1} / ${DrillPage.rounds}')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('$_score', style: text.titleLarge?.copyWith(color: kBeatAmber))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LinearProgressIndicator(
            value: _index / DrillPage.rounds,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              gradient: heroGradient(Theme.of(context).brightness),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.all(24),
            child: Text(q.prompt,
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(color: Colors.white, height: 1.35)),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < q.options.length; i++) ...[
            _Option(
              text: q.options[i],
              state: _chosen == null
                  ? null
                  : (i == q.answer ? true : (i == _chosen ? false : null)),
              dim: _chosen != null && i != q.answer && i != _chosen,
              onTap: () => _choose(i),
            ),
            const SizedBox(height: 10),
          ],
          if (_chosen != null && _chosen != q.answer)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr(zh: '答案:${q.options[q.answer]}', en: 'Answer: ${q.options[q.answer]}'),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.text, required this.state, required this.dim, required this.onTap});
  final String text;
  final bool? state;
  final bool dim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = state == null ? cs.surfaceContainerHigh : (state! ? kInTuneGreen.withValues(alpha: 0.22) : kOffCoral.withValues(alpha: 0.22));
    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: state == null ? Colors.transparent : (state! ? kInTuneGreen : kOffCoral), width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
                if (state != null) Icon(state! ? Icons.check_circle : Icons.cancel, color: state! ? kInTuneGreen : kOffCoral),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
