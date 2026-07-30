import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/l10n.dart';
import 'note.dart';
import 'transcript_text.dart';
import 'ui_common.dart';

/// One note, fully editable. System dictation gets words right more often than
/// punctuation, so editing is a first-class part of the flow — the text field is
/// the page, and edits save on the way out.
class NoteDetailPage extends StatefulWidget {
  const NoteDetailPage({super.key, required this.note, required this.store});

  final Note note;
  final NoteStore store;

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage>
    with WidgetsBindingObserver {
  late final TextEditingController _textCtrl =
      TextEditingController(text: widget.note.text);

  bool get _dirty => _textCtrl.text.trim() != widget.note.text;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android can evict a backgrounded process without ever popping this route,
    // so corrections are committed as soon as the app loses the foreground.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _save(quiet: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({bool quiet = false}) async {
    if (!_dirty) return;
    widget.note.text = _textCtrl.text.trim();
    await widget.store.update(widget.note);
    if (!quiet && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(zh: '已保存', en: 'Saved'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      // Never lose a dictation: edits are saved when the page closes.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save(quiet: true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: tr(zh: '复制', en: 'Copy'),
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _textCtrl.text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr(zh: '已复制', en: 'Copied'))),
                );
              },
            ),
            IconButton(
              tooltip: tr(zh: '分享', en: 'Share'),
              icon: const Icon(Icons.share_outlined),
              onPressed: _textCtrl.text.trim().isEmpty
                  ? null
                  : () => SharePlus.instance
                      .share(ShareParams(text: _textCtrl.text)),
            ),
            IconButton(
              tooltip: tr(zh: '保存', en: 'Save'),
              icon: const Icon(Icons.check),
              onPressed: _save,
            ),
          ],
        ),
        body: Column(
          children: [
            // Same tinted chips as the timeline card — one visual language for
            // the same three facts.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  InfoChip(
                    icon: Icons.schedule,
                    label: formatNoteStamp(note.createdAt),
                  ),
                  const SizedBox(width: 8),
                  InfoChip(
                    icon: Icons.timer_outlined,
                    label: formatElapsed(Duration(milliseconds: note.durationMs)),
                  ),
                  const Spacer(),
                  Builder(builder: (context) {
                    final cjk = isCjkText(_textCtrl.text);
                    return InfoChip(
                      icon: Icons.short_text,
                      label: formatLength(
                        countUnits(_textCtrl.text, cjk: cjk),
                        cjk: cjk,
                      ),
                    );
                  }),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: TextField(
                    controller: _textCtrl,
                    maxLines: null,
                    expands: true,
                    onChanged: (_) => setState(() {}),
                    textAlignVertical: TextAlignVertical.top,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(height: 1.5),
                    decoration: InputDecoration(
                      hintText: tr(
                        zh: '转写的文字在这里,可直接编辑',
                        en: 'Your dictated text — edit it freely',
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: false,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
