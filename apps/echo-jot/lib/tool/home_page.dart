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
              ? Center(
                  child: Text(
                    _searchCtrl.text.isEmpty
                        ? '点下面的按钮,说出你的第一条笔记'
                        : '没有匹配的笔记',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
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
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_recording)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '录音中 ${_fmtElapsed()}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                FloatingActionButton.large(
                  onPressed: _toggleRecording,
                  backgroundColor: _recording
                      ? Theme.of(context).colorScheme.error
                      : null,
                  child: Icon(_recording ? Icons.stop : Icons.mic, size: 36),
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

    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          onTap: onTap,
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
              Text(durText, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
