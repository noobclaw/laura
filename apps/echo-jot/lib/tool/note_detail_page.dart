import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'note.dart';
import 'transcriber.dart';

class NoteDetailPage extends StatefulWidget {
  const NoteDetailPage({
    super.key,
    required this.note,
    required this.store,
    required this.transcriber,
  });

  final Note note;
  final NoteStore store;
  final Transcriber transcriber;

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  late final TextEditingController _textCtrl;
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.note.text);
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    widget.store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (!mounted) return;
    // Reflect background transcription finishing while this page is open.
    if (widget.note.status == NoteStatus.done &&
        _textCtrl.text.isEmpty &&
        widget.note.text.isNotEmpty) {
      _textCtrl.text = widget.note.text;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _player.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
    } else {
      await _player.play(DeviceFileSource(widget.note.audioPath));
      setState(() => _playing = true);
    }
  }

  Future<void> _save() async {
    widget.note.text = _textCtrl.text;
    await widget.store.update(widget.note);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return Scaffold(
      appBar: AppBar(
        title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: note.text.isEmpty
                ? null
                : () => SharePlus.instance.share(ShareParams(text: note.text)),
          ),
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: Column(
        children: [
          if (note.status == NoteStatus.failed)
            MaterialBanner(
              content: const Text('转写失败'),
              actions: [
                TextButton(
                  onPressed: () => widget.transcriber.retry(note),
                  child: const Text('重试'),
                ),
              ],
            ),
          if (note.status == NoteStatus.pending ||
              note.status == NoteStatus.transcribing)
            const LinearProgressIndicator(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _textCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: '转写文本会出现在这里,可直接编辑',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    iconSize: 32,
                    icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                    onPressed: _togglePlay,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '录音 ${Duration(milliseconds: note.durationMs).inSeconds}s',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
