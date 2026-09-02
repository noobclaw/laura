import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'dictation_controller.dart';
import 'note.dart';
import 'note_detail_page.dart';
import 'paywall.dart';
import 'transcript_text.dart';
import 'ui_common.dart';

class EchoJotHome extends StatefulWidget {
  const EchoJotHome({super.key, required this.store, this.controller});

  final NoteStore store;

  /// Shared app-wide controller (owned by EchoJotTool). Tests may omit it.
  final DictationController? controller;

  @override
  State<EchoJotHome> createState() => _EchoJotHomeState();
}

class _EchoJotHomeState extends State<EchoJotHome> with WidgetsBindingObserver {
  late final DictationController _controller =
      widget.controller ?? DictationController();
  late final bool _ownsController = widget.controller == null;
  final _searchCtrl = TextEditingController();
  Timer? _ticker;

  /// True while [_finishSession] is running — keeps the controller's own
  /// state change from triggering a second save of the same session.
  bool _finishing = false;

  /// Last known "a session is live" state, so a session the recognizer ends on
  /// its own (fatal error) still gets saved instead of vanishing.
  bool _wasLive = false;

  NoteStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onControllerChanged);
    _store.addListener(_onStoreChanged);
    // Probe the on-device recognizer up front so the home screen can tell the
    // user the truth before they tap the button.
    unawaited(_controller.probe());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _store.removeListener(_onStoreChanged);
    if (_ownsController) _controller.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    final live =
        _controller.listening || _controller.state == DictationState.finishing;
    if (_wasLive && !live && !_finishing) {
      // The session ended without us asking (recognizer failure): save what was
      // already dictated and surface the reason.
      _wasLive = false;
      unawaited(_finishSession());
      return;
    }
    _wasLive = live;
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The system recognizer is a foreground-only facility: finish and save
    // rather than leave a session half-listening in the background.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_controller.listening ||
          _controller.state == DictationState.finishing) {
        unawaited(_finishSession(background: true));
      }
    } else if (state == AppLifecycleState.resumed) {
      // The user may have installed a language pack while we were away.
      if (_controller.capabilities?.ready != true) {
        unawaited(_controller.probe());
      }
    }
  }

  Future<void> _toggle() async {
    if (_controller.listening ||
        _controller.state == DictationState.finishing) {
      await _finishSession();
      return;
    }
    if (!await checkNoteQuota(context, _store)) return;
    final started = await _controller.start();
    if (!started) {
      _showControllerMessage();
      return;
    }
    _wasLive = true;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _finishSession({bool background = false}) async {
    if (_finishing) return;
    _finishing = true;
    try {
      _ticker?.cancel();
      _ticker = null;
      final startedAt = DateTime.now().subtract(_controller.elapsed);
      final durationMs = _controller.elapsed.inMilliseconds;
      final text = background
          ? await _controller.stopForBackground()
          : await _controller.stop();
      final trimmed = (text ?? '').trim();
      if (trimmed.isNotEmpty) {
        await _store.add(Note(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          createdAt: startedAt,
          durationMs: durationMs,
          text: trimmed,
          language: _controller.language,
        ));
      } else if (!background && _controller.message == null) {
        _snack(tr(
          zh: '没听到内容,这条没有保存。',
          en: 'Nothing was heard — no note saved.',
        ));
      }
      _showControllerMessage();
    } finally {
      _finishing = false;
      _wasLive = false;
    }
  }

  void _showControllerMessage() {
    final msg = _controller.message;
    if (msg == null) return;
    final denied = _controller.permissionPermanentlyDenied;
    _controller.clearMessage();
    // A permanently denied microphone must always have a way out of the app —
    // the banner only shows when the recognizer itself is missing.
    _snack(
      msg,
      action: denied
          ? SnackBarAction(
              label: tr(zh: '去设置', en: 'Settings'),
              onPressed: _controller.openSystemSettings,
            )
          : null,
    );
  }

  void _snack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        action: action,
        duration: Duration(seconds: action == null ? 4 : 8),
      ));
  }

  /// A note is often the only copy of a thought, and a swipe is easy to trigger
  /// by accident while scrolling — so deletion is always undoable.
  Future<void> _deleteWithUndo(Note note) async {
    final index = _store.indexOf(note);
    await _store.remove(note);
    if (!mounted) return;
    _snack(
      tr(zh: '已删除「${note.title}」', en: 'Deleted "${note.title}"'),
      action: SnackBarAction(
        label: tr(zh: '撤销', en: 'Undo'),
        onPressed: () => _store.insertAt(index < 0 ? 0 : index, note),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes = _store.search(_searchCtrl.text);
    final caps = _controller.capabilities;
    final searching = _searchCtrl.text.isNotEmpty;

    return Column(
      children: [
        if (_store.loadError != null) const _LoadErrorNotice(),
        if (caps != null && !caps.ready && !_controller.listening)
          _CapabilityNotice(
            controller: _controller,
            onRecheck: () async {
              await _controller.probe();
              if (!mounted) return;
              _snack(_controller.capabilities?.ready == true
                  ? tr(zh: '设备端识别已就绪', en: 'On-device recognition is ready')
                  : tr(
                      zh: '仍不可用 — 设备端识别还没就绪',
                      en: 'Still unavailable — on-device recognition is not ready',
                    ));
            },
          ),
        if (_store.notes.length > 4 || searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: tr(zh: '搜索笔记内容…', en: 'Search notes…'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searching
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
            ),
          ),
        Expanded(
          child: notes.isEmpty
              ? EmptyState(
                  icon: searching ? Icons.search_off : Icons.graphic_eq,
                  title: searching
                      ? tr(zh: '没有匹配的笔记', en: 'No matching notes')
                      : tr(zh: '说出第一条笔记', en: 'Speak your first note'),
                  body: searching
                      ? tr(zh: '换个关键词再试试。', en: 'Try another keyword.')
                      : tr(
                          zh: '点下面的话筒开始说,文字会边说边出现——全程在这台手机上完成,不保存录音。\n\n'
                              '试试说:「提醒我明天上午给房东打电话」',
                          en: 'Tap the mic and start talking. Text appears as you '
                              'speak — all on this phone, and no audio is kept.\n\n'
                              'Try: "remind me to call the landlord tomorrow"',
                        ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: notes.length,
                  itemBuilder: (context, i) => NoteCard(
                    note: notes[i],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            NoteDetailPage(note: notes[i], store: _store),
                      ),
                    ),
                    onDelete: () => _deleteWithUndo(notes[i]),
                  ),
                ),
        ),
        _DictationPanel(
          controller: _controller,
          onToggle: _toggle,
        ),
      ],
    );
  }
}

/// Shown when the notes file could not be read at launch. The bad file is kept
/// (renamed) rather than overwritten, and the user is told — losing notes
/// silently would be the worst failure this app can have.
class _LoadErrorNotice extends StatelessWidget {
  const _LoadErrorNotice();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                zh: '上次的笔记文件读不出来,已原样备份到应用目录(notes.json.corrupt-…),'
                    '这里从空列表开始。新笔记会正常保存。',
                en: 'The previous notes file could not be read. It was kept as '
                    'notes.json.corrupt-… in the app folder and the list starts '
                    'empty. New notes save normally.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onErrorContainer,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Honest, actionable banner when the system has no on-device recognizer: the
/// one thing we must never do is quietly transcribe in the cloud instead.
class _CapabilityNotice extends StatelessWidget {
  const _CapabilityNotice({required this.controller, required this.onRecheck});

  final DictationController controller;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final permanentlyDenied = controller.permissionPermanentlyDenied;
    // secondaryContainer keeps the banner inside the teal palette — the default
    // tertiary tone lands on lilac and fights the hero.
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.privacy_tip_outlined,
                  size: 20, color: cs.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(zh: '需要系统的设备端语音识别', en: 'On-device recognition needed'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            DictationController.noOnDeviceHelp,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSecondaryContainer.withValues(alpha: 0.85),
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                onPressed: onRecheck,
                style: TextButton.styleFrom(
                    foregroundColor: cs.onSecondaryContainer),
                child: Text(tr(zh: '重新检测', en: 'Check again')),
              ),
              if (permanentlyDenied)
                TextButton(
                  onPressed: controller.openSystemSettings,
                  style: TextButton.styleFrom(
                      foregroundColor: cs.onSecondaryContainer),
                  child: Text(tr(zh: '去系统设置', en: 'Open settings')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The hero: a tinted panel that turns into a live transcript while dictating.
class _DictationPanel extends StatelessWidget {
  const _DictationPanel({required this.controller, required this.onToggle});

  final DictationController controller;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final listening = controller.listening;
    final finishing = controller.state == DictationState.finishing;

    // The panel must read as a container: starting the gradient at cs.surface
    // (== scaffold background) made its 28px radius and top edge invisible.
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.surfaceContainerLow,
            listening
                ? Color.alphaBlend(
                    cs.primary.withValues(alpha: 0.18),
                    cs.surfaceContainerHigh,
                  )
                : cs.surfaceContainerHigh,
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (listening || finishing) ...[
                // Flexible so a very large system font (or a short screen) can
                // shrink the transcript box instead of overflowing the panel.
                Flexible(
                  child: _LiveTranscript(text: controller.previewText),
                ),
                const SizedBox(height: 16),
                LevelMeter(levels: controller.levels),
                const SizedBox(height: 12),
                Text(
                  finishing
                      ? tr(zh: '正在收尾…', en: 'Wrapping up…')
                      : formatElapsed(controller.elapsed),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    zh: '边说边转文字 · 不保存录音',
                    en: 'Transcribing as you speak · no audio kept',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
              ] else ...[
                // Extra inset: at titleLarge this line otherwise reaches the
                // panel's rounded corners on narrow (360dp) devices.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    tr(
                      zh: '点一下开始说,边说边出字',
                      en: 'Tap to talk, watch it type',
                    ),
                    textAlign: TextAlign.center,
                    // The hero line must outrank card titles in the type scale.
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    zh: '设备端识别 · 声音不出这台手机',
                    en: 'On-device recognition · your voice stays here',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
              ],
              MicButton(
                listening: listening || finishing,
                onTap: onToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The words as they arrive. Auto-scrolls to the newest line and keeps a fixed
/// height so the button below never jumps around.
class _LiveTranscript extends StatefulWidget {
  const _LiveTranscript({required this.text});

  final String text;

  @override
  State<_LiveTranscript> createState() => _LiveTranscriptState();
}

class _LiveTranscriptState extends State<_LiveTranscript> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant _LiveTranscript old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = widget.text.trim().isEmpty;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64, maxHeight: 116),
      child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        // The live transcript is the emotional payload — give it a real surface
        // with an edge, not a barely-there tint.
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: SingleChildScrollView(
        controller: _scroll,
        child: Text(
          empty
              ? tr(zh: '开始说话吧,文字会出现在这里…', en: 'Start talking — text appears here…')
              : widget.text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.45,
                color: empty ? cs.onSurfaceVariant : cs.onSurface,
                fontStyle: empty ? FontStyle.italic : FontStyle.normal,
              ),
        ),
      ),
      ),
    );
  }
}

/// Timeline card for one note.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cjk = isCjkText(note.text);
    final units = countUnits(note.text, cjk: cjk);

    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        // Must match cardTheme.margin, or the red backdrop pokes out past the
        // card while swiping.
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatNoteStamp(note.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                if (note.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    note.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.72),
                          height: 1.35,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    InfoChip(
                      icon: Icons.timer_outlined,
                      label: formatElapsed(
                          Duration(milliseconds: note.durationMs)),
                    ),
                    const SizedBox(width: 8),
                    InfoChip(
                      icon: Icons.short_text,
                      label: formatLength(units, cjk: cjk),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
