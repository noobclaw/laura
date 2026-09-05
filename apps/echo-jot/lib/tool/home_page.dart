import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'dictation_controller.dart';
import 'dictation_engine.dart';
import 'dictation_language.dart';
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
    // Whisper's transcribing state counts as live: the session is not over
    // until the text exists.
    final live = _controller.busy;
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
      } else if (!_controller.busy) {
        // A Whisper transcription in flight is left alone (it needs no mic);
        // an idle app gives the parked model's memory back.
        unawaited(_controller.releaseWhisperIfIdle());
      }
    } else if (state == AppLifecycleState.resumed) {
      // The user may have installed a language pack while we were away.
      if (_controller.capabilities?.ready != true) {
        unawaited(_controller.probe());
      }
    }
  }

  Future<void> _toggle() async {
    if (_controller.transcribing) {
      // The tap while Whisper works = "stop after this chunk, keep what you
      // have"; _finishSession is already awaiting the same stop().
      _controller.cancelTranscription();
      return;
    }
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
        final saveErr = _store.takeSaveError();
        if (saveErr != null) {
          _snack(tr(
            zh: '笔记没能写入存储($saveErr)。请先复制文字,再检查手机空间。',
            en: 'The note could not be written to storage ($saveErr). Copy the text, then check free space.',
          ));
        }
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
    final denied = _controller.permissionPermanentlyDenied ||
        _controller.lastErrorNeedsSettings;
    _controller.clearMessage();
    // Anything the user fixes in system settings (permission, dictation
    // switched off, no language pack) gets a shortcut right on the message.
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
        duration: Duration(seconds: action == null ? 4 : 12),
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
        // The banner is about the *system* engine; with Whisper selected the
        // system's language packs are irrelevant.
        if (caps != null &&
            !caps.ready &&
            !_controller.busy &&
            _controller.engine == DictationEngine.system)
          _CapabilityNotice(
            controller: _controller,
            onUseWhisper: () async {
              await DictationEnginePref.set(DictationEngine.whisper);
              if (!mounted) return;
              setState(() {});
              _snack(tr(
                zh: '已切换到 Whisper 离线引擎:说完停止后开始转写。',
                en: 'Switched to the Whisper offline engine: transcription '
                    'starts when you stop.',
              ));
            },
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
        if (_store.notes.length > 1 || searching)
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
                          zh: '点下面的话筒开始说,说完就是一条可搜索的文字笔记——'
                              '转写全程在这台手机上完成,不上传、不留录音。\n\n'
                              '试试说:「提醒我明天上午给房东打电话」',
                          en: 'Tap the mic and start talking; what you say becomes '
                              'a searchable note — transcribed on this phone, '
                              'nothing uploaded, no recording kept.\n\n'
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
        // The engine chip must follow the preference, which changes outside
        // the controller (settings page, the banner's switch button).
        ValueListenableBuilder<DictationEngine>(
          valueListenable: DictationEnginePref.current,
          builder: (context, _, _) => _DictationPanel(
            controller: _controller,
            onToggle: _toggle,
          ),
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
  const _CapabilityNotice({
    required this.controller,
    required this.onRecheck,
    required this.onUseWhisper,
  });

  final DictationController controller;
  final VoidCallback onRecheck;

  /// The way out that needs no system change: the bundled Whisper engine.
  final VoidCallback onUseWhisper;

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
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: onUseWhisper,
                icon: const Icon(Icons.memory_outlined, size: 18),
                label: Text(tr(zh: '改用 Whisper 离线', en: 'Use Whisper offline')),
              ),
              TextButton(
                onPressed: onRecheck,
                style: TextButton.styleFrom(
                    foregroundColor: cs.onSecondaryContainer),
                child: Text(tr(zh: '重新检测', en: 'Check again')),
              ),
              TextButton(
                onPressed: controller.openSystemSettings,
                style: TextButton.styleFrom(
                    foregroundColor: cs.onSecondaryContainer),
                child: Text(permanentlyDenied
                    ? tr(zh: '去系统设置', en: 'Open settings')
                    : tr(zh: '打开设置', en: 'Open settings')),
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
    final transcribing = controller.transcribing;
    final engine = controller.engine;
    final whisper = engine == DictationEngine.whisper;

    // The panel must read as a container: starting the gradient at cs.surface
    // (== scaffold background) made its 28px radius and top edge invisible.
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.surfaceContainerLow,
            listening || transcribing
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
              if (transcribing) ...[
                _TranscribingStatus(controller: controller),
                const SizedBox(height: 10),
              ] else if (listening || finishing) ...[
                // Flexible so a very large system font (or a short screen) can
                // shrink the transcript box instead of overflowing the panel.
                Flexible(
                  child: _LiveTranscript(
                    text: controller.previewText,
                    placeholder: whisper
                        ? tr(
                            zh: '正在录音…停止后开始转写',
                            en: 'Recording… transcription starts when you stop',
                          )
                        : tr(
                            zh: '开始说话吧,文字会出现在这里…',
                            en: 'Start talking — text appears here…',
                          ),
                  ),
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
                  whisper
                      ? tr(
                          zh: 'Whisper 离线 · 停止后转写 · 录音只在本机,转完即删',
                          en: 'Whisper offline · transcribes after stop · '
                              'recording stays here, deleted once transcribed',
                        )
                      : tr(
                          zh: '系统识别 · 边说边转文字 · 不保存录音',
                          en: 'System recognizer · transcribing as you speak · '
                              'no audio kept',
                        ),
                  textAlign: TextAlign.center,
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
                    whisper
                        ? tr(
                            zh: '点一下开始说,停止后出字',
                            en: 'Tap to talk, text after you stop',
                          )
                        : tr(
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
                  whisper
                      ? tr(
                          zh: '内置 Whisper 模型 · 声音不出这台手机',
                          en: 'Bundled Whisper model · your voice stays here',
                        )
                      : tr(
                          zh: '设备端识别 · 声音不出这台手机',
                          en: 'On-device recognition · your voice stays here',
                        ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                // Two chips: which engine, and which language it listens for —
                // the single most common "it only understands English"
                // complaint is a Chinese speaker on an English-system phone,
                // and the second most common is the system engine itself.
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    ActionChip(
                      avatar: Icon(DictationEnginePref.icon(engine), size: 18),
                      label: Text(DictationEnginePref.label(engine)),
                      tooltip: tr(zh: '转写引擎', en: 'Transcription engine'),
                      onPressed: () => DictationEnginePref.pick(context),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.translate, size: 18),
                      label: Text(DictationLanguage.currentLabel()),
                      tooltip: tr(zh: '听写语言', en: 'Dictation language'),
                      onPressed: () =>
                          DictationLanguage.pick(context, controller),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              MicButton(
                listening: listening || finishing || transcribing,
                icon: transcribing ? Icons.hourglass_top_rounded : null,
                semanticsLabel: transcribing
                    ? tr(zh: '提前结束转写', en: 'End transcription early')
                    : null,
                onTap: onToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whisper is working on the stopped recording: progress bar, chunk count,
/// and the one-tap way out (the mic button cancels after the current chunk).
class _TranscribingStatus extends StatelessWidget {
  const _TranscribingStatus({required this.controller});

  final DictationController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = controller.chunkCount;
    final chunkLine = total > 1
        ? tr(
            zh: '第 ${controller.chunk} / $total 段',
            en: 'part ${controller.chunk} of $total',
          )
        : null;
    final pct = (controller.progress * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          controller.cancelRequested
              ? tr(zh: '正在结束这一段…', en: 'Finishing this part…')
              : tr(zh: '正在转写…', en: 'Transcribing…'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: controller.progress <= 0 ? null : controller.progress,
            minHeight: 8,
            semanticsLabel: tr(zh: '转写进度', en: 'Transcription progress'),
            semanticsValue: '$pct%',
          ),
        ),
        const SizedBox(height: 10),
        Text(
          [
            'Whisper',
            ?chunkLine,
            if (controller.progress > 0) '$pct%',
            tr(zh: '只在本机', en: 'on this phone only'),
          ].join(' · '),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          tr(
            zh: '点按钮可提前结束,已转好的部分会保存',
            en: 'Tap the button to end early; what is done so far is kept',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

/// The words as they arrive. Auto-scrolls to the newest line and keeps a fixed
/// height so the button below never jumps around.
class _LiveTranscript extends StatefulWidget {
  const _LiveTranscript({required this.text, required this.placeholder});

  final String text;

  /// Shown while there is no text yet — differs per engine (Whisper has
  /// nothing to show until the recording stops).
  final String placeholder;

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
          empty ? widget.placeholder : widget.text,
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
