import 'dart:async';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'note.dart';
import 'note_detail_page.dart';
import 'paywall.dart';
import 'transcriber.dart';

class EchoJotHome extends StatefulWidget {
  const EchoJotHome({super.key});

  @override
  State<EchoJotHome> createState() => _EchoJotHomeState();
}

class _EchoJotHomeState extends State<EchoJotHome> {
  NoteStore? _store;
  Transcriber? _transcriber;
  final _recorder = AudioRecorder();
  final _searchCtrl = TextEditingController();
  Object? _initError;

  bool _recording = false;
  DateTime? _recordStart;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final store = await NoteStore.open();
      final transcriber = Transcriber(store);
      setState(() {
        _store = store;
        _transcriber = transcriber;
      });
      store.addListener(_onStoreChanged);
      // Install the model and pick up notes interrupted mid-transcription.
      unawaited(transcriber.ensureModelInstalled().then((_) {
        if (mounted) transcriber.drainQueue();
      }));
    } catch (e) {
      setState(() => _initError = e);
    }
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _searchCtrl.dispose();
    _recorder.dispose();
    _store?.removeListener(_onStoreChanged);
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final store = _store;
    final transcriber = _transcriber;
    if (store == null || transcriber == null) return;

    if (_recording) {
      _ticker?.cancel();
      final path = await _recorder.stop();
      final start = _recordStart;
      setState(() => _recording = false);
      if (path == null || start == null) return;
      final note = Note(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: start,
        audioPath: path,
        durationMs: DateTime.now().difference(start).inMilliseconds,
      );
      await store.add(note);
      unawaited(transcriber.drainQueue());
      return;
    }

    if (!await checkNoteQuota(context, store.notes.length)) return;
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能录音')),
        );
      }
      return;
    }
    final dir = store.audioDir.path;
    final path = '$dir/${DateTime.now().millisecondsSinceEpoch}.wav';
    // 16kHz mono PCM WAV: whisper's native input, no conversion step.
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    setState(() {
      _recording = true;
      _recordStart = DateTime.now();
    });
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  String _fmtElapsed() {
    final start = _recordStart;
    if (start == null) return '0:00';
    final s = DateTime.now().difference(start).inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Center(child: Text('初始化失败:$_initError'));
    }
    final store = _store;
    if (store == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final notes = store.search(_searchCtrl.text);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索笔记内容…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: notes.isEmpty
              ? _EmptyState(
                  icon: _searchCtrl.text.isEmpty
                      ? Icons.mic_none
                      : Icons.search_off,
                  title: _searchCtrl.text.isEmpty ? '还没有笔记' : '没有匹配的笔记',
                  body: _searchCtrl.text.isEmpty
                      ? '点下面的按钮,说出你的第一条笔记——松手即转成文字,全程离线。'
                      : '换个关键词再试试。',
                )
              : ListView.builder(
                  itemCount: notes.length,
                  itemBuilder: (context, i) => _NoteCard(
                    note: notes[i],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => NoteDetailPage(
                          note: notes[i],
                          store: store,
                          transcriber: _transcriber!,
                        ),
                      ),
                    ),
                    onDelete: () => store.remove(notes[i]),
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_recording) ...[
                  // Live level meter driven by the recorder's amplitude stream —
                  // the moving bars are the app's "we're listening" signal.
                  _AmplitudeMeter(recorder: _recorder),
                  const SizedBox(height: 14),
                  Text(
                    '录音中 ${_fmtElapsed()}',
                    style:
                        Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                  ),
                  const SizedBox(height: 12),
                ],
                _RecordButton(
                  recording: _recording,
                  onTap: _toggleRecording,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  String get _statusLabel => switch (note.status) {
        NoteStatus.pending => '排队转写中…',
        NoteStatus.transcribing => '转写中…',
        NoteStatus.failed => '转写失败,点开重试',
        NoteStatus.done => '',
      };

  @override
  Widget build(BuildContext context) {
    final d = Duration(milliseconds: note.durationMs);
    final durText =
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    final date = note.createdAt;
    final dateText =
        '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';

    final cs = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        color: cs.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        child: ListTile(
          onTap: onTap,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.graphic_eq, color: cs.primary, size: 22),
          ),
          title: Text(
            note.status == NoteStatus.done ? note.title : _statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: note.text.isEmpty
              ? null
              : Text(note.text, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(dateText, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                durText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A warm, consistent empty state: an icon in a soft tinted circle, a heading,
/// and a supporting line — so a blank list feels designed, not abandoned.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: cs.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.65),
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A live loudness meter driven by the recorder's amplitude stream: a rolling
/// row of bars that dance with the incoming level. Purely visual — if the
/// platform has no amplitude support the bars simply stay flat (no crash).
class _AmplitudeMeter extends StatefulWidget {
  const _AmplitudeMeter({required this.recorder});

  final AudioRecorder recorder;

  @override
  State<_AmplitudeMeter> createState() => _AmplitudeMeterState();
}

class _AmplitudeMeterState extends State<_AmplitudeMeter> {
  static const int _barCount = 27;
  static const double _minDb = -45; // quieter than this reads as silence

  final List<double> _levels = List<double>.filled(_barCount, 0);
  StreamSubscription<Amplitude>? _sub;

  @override
  void initState() {
    super.initState();
    try {
      _sub = widget.recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen(_onAmp, onError: (Object _) {});
    } catch (_) {
      // Some platforms / no-mic devices don't emit amplitude — leave it flat.
    }
  }

  void _onAmp(Amplitude amp) {
    final db = amp.current;
    final double norm = (db.isNaN || db.isInfinite)
        ? 0
        : ((db - _minDb) / (0 - _minDb)).clamp(0.0, 1.0);
    if (!mounted) return;
    setState(() {
      _levels.removeAt(0);
      _levels.add(norm);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final level in _levels)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: 4,
                height: 4 + level * 34,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    cs.primary.withValues(alpha: 0.5),
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

/// The record button, wrapped in a soft pulsing ring while recording so the
/// live state reads at a glance even away from the meter.
class _RecordButton extends StatefulWidget {
  const _RecordButton({required this.recording, required this.onTap});

  final bool recording;
  final VoidCallback onTap;

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.recording) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _RecordButton old) {
    super.didUpdateWidget(old);
    if (widget.recording && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.recording && _pulse.isAnimating) {
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
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.recording)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = _pulse.value;
                return Container(
                  width: 96 + t * 36,
                  height: 96 + t * 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.error.withValues(alpha: (1 - t) * 0.22),
                  ),
                );
              },
            ),
          FloatingActionButton.large(
            onPressed: widget.onTap,
            backgroundColor: widget.recording ? cs.error : null,
            child: Icon(widget.recording ? Icons.stop : Icons.mic, size: 36),
          ),
        ],
      ),
    );
  }
}
