import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../../core/review_prompt.dart';
import '../models.dart';
import '../store.dart';
import 'history_screen.dart';
import 'markdown_controller.dart';
import 'widgets.dart';

/// The writing surface.
///
/// Three rules from PLAN.md §3, all of them written against a specific
/// complaint about the incumbent:
///
/// 1. **The toolbar above the keyboard is always there.** It lives in the
///    scaffold's bottom bar, not in a popup that can fail to open
///    ("None of the tools above the keyboard open nor work").
/// 2. **Nothing interrupts writing.** Saving is silent and continuous; there
///    is no save button and no modal.
/// 3. **Nothing typed is ever lost.** The text is written to disk on a short
///    debounce, on every lifecycle change, and when the screen closes; a
///    version snapshot is kept whenever a session changed the scene.
class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.store,
    required this.projectId,
    required this.sceneId,
  });

  final DraftbookStore store;
  final String projectId;
  final String sceneId;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const Duration _autosave = Duration(milliseconds: 700);

  final MarkdownEditingController _controller = MarkdownEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  Timer? _debounce;
  Timer? _barTick;
  AppLifecycleListener? _lifecycle;
  String _sceneId = '';
  String _sessionStartBody = '';
  bool _dirty = false;

  Project? get _project => widget.store.projectById(widget.projectId);
  SceneRef? get _ref {
    final p = _project;
    if (p == null) return null;
    return widget.store.findScene(p, _sceneId);
  }

  @override
  void initState() {
    super.initState();
    _sceneId = widget.sceneId;
    _loadScene(_sceneId, focus: true);
    _controller.addListener(_onChanged);
    // A phone call, a task switch or a swipe to the home screen must not cost
    // the last few sentences — and the store's own write debounce has to be
    // cut short too, because there may be no next tick.
    _lifecycle = AppLifecycleListener(onStateChange: (s) {
      if (s != AppLifecycleState.resumed) {
        _saveNow();
        widget.store.saveNow();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _barTick?.cancel();
    _lifecycle?.dispose();
    _saveNow();
    _closeSession(countAction: true);
    widget.store.saveNow();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _loadScene(String id, {bool focus = false}) {
    final p = _project;
    if (p == null) return;
    final ref = widget.store.findScene(p, id);
    if (ref == null) return;
    _sceneId = id;
    _sessionStartBody = ref.scene.body;
    _controller.value = TextEditingValue(
      text: ref.scene.body,
      selection: TextSelection.collapsed(offset: ref.scene.body.length),
    );
    _dirty = false;
    widget.store.noteSceneOpened(p, ref.scene);
    if (focus && ref.scene.body.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  void _onChanged() {
    if (!_dirty) {
      // First change of this session, and `scene.body` is still the text the
      // session started with — keep it. Without this, a scene written in one
      // sitting has no recovery point at all: select-all + one keystroke would
      // overwrite it, and the only version ever taken (on leaving) would be
      // the damage. `snapshotScene` de-dupes, so this does not grow history.
      final p = _project;
      final ref = _ref;
      if (p != null && ref != null) widget.store.snapshotScene(p, ref.scene);
    }
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(_autosave, _saveNow);
    // The bottom bar's live count is throttled: a rebuild per keystroke means
    // re-counting the whole scene per keystroke, which a pasted chapter feels.
    _barTick ??= Timer(const Duration(milliseconds: 220), () {
      _barTick = null;
      if (mounted) setState(() {});
    });
  }

  void _saveNow() {
    _debounce?.cancel();
    if (!_dirty) return;
    final p = _project;
    final ref = _ref;
    if (p == null || ref == null) return;
    widget.store.updateSceneBody(p, ref.scene, _controller.text);
    _dirty = false;
  }

  /// Ends a writing session: keeps a version if the text changed, and — only
  /// when the writer is actually leaving — counts the session towards the
  /// store-rating prompt.
  void _closeSession({required bool countAction}) {
    final p = _project;
    final ref = _ref;
    if (p == null || ref == null) return;
    if (ref.scene.body == _sessionStartBody) return;
    widget.store.snapshotScene(p, ref.scene);
    if (!countAction) return;
    // Core action for the rating prompt (PLAN.md G8b-7): a writing session
    // that actually changed the manuscript. Never fired while the editor is
    // still open — "no dialogs interrupt your writing" is a promise in the
    // store listing, and the review sheet is a dialog.
    unawaited(ReviewPrompt.noteCoreAction());
  }

  /// Move to another scene without leaving the editor — the session for the
  /// scene being left is closed exactly as if the screen had closed, except
  /// that the writer has not left, so no rating prompt.
  void _goTo(SceneRef target) {
    _saveNow();
    _closeSession(countAction: false);
    setState(() => _loadScene(target.scene.id));
    // A short scene after a long one would otherwise open scrolled past its
    // own end.
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Flattened scene order, for the previous/next buttons.
  List<SceneRef> _allScenes() {
    final p = _project;
    if (p == null) return const [];
    final out = <SceneRef>[];
    for (var ci = 0; ci < p.chapters.length; ci++) {
      final c = p.chapters[ci];
      for (var si = 0; si < c.scenes.length; si++) {
        out.add(SceneRef(
          project: p,
          chapter: c,
          scene: c.scenes[si],
          chapterIndex: ci,
          sceneIndex: si,
        ));
      }
    }
    return out;
  }

  void _apply(TextEditingValue next) {
    _controller.value = next;
    _focus.requestFocus();
  }

  Future<void> _renameScene() async {
    final p = _project;
    final ref = _ref;
    if (p == null || ref == null) return;
    final titleCtl = TextEditingController(text: ref.scene.title);
    final synopsisCtl = TextEditingController(text: ref.scene.synopsis);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '场景信息', en: 'Scene details')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr(zh: '标题', en: 'Title'),
                hintText: tr(zh: '例如:雨夜的电话', en: 'e.g. The call at midnight'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: synopsisCtl,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr(zh: '梗概(只给自己看)', en: 'Synopsis (for your eyes)'),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(zh: '保存', en: 'Save')),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.store.updateScene(p, ref.scene,
          title: titleCtl.text, synopsis: synopsisCtl.text);
      if (mounted) setState(() {});
    }
    titleCtl.dispose();
    synopsisCtl.dispose();
  }

  Future<void> _pickStatus() async {
    final p = _project;
    final ref = _ref;
    if (p == null || ref == null) return;
    final chosen = await showModalBottomSheet<SceneStatus>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in SceneStatus.values)
              ListTile(
                leading: StatusDot(status: s, size: 12),
                title: Text(sceneStatusLabel(s)),
                trailing: ref.scene.status == s
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      widget.store.updateScene(p, ref.scene, status: chosen);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openHistory() async {
    final p = _project;
    final ref = _ref;
    if (p == null || ref == null) return;
    _saveNow();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HistoryScreen(
        store: widget.store,
        projectId: p.id,
        sceneId: ref.scene.id,
      ),
    ));
    if (!mounted) return;
    final now = _ref;
    if (now == null) return;
    // A restore rewrote the body while we were away. The session restarts from
    // the restored text: it is not writing, so it must not count towards the
    // rating prompt and must not be snapshotted again as if it were.
    if (now.scene.body != _controller.text) {
      _controller.value = TextEditingValue(
        text: now.scene.body,
        selection: TextSelection.collapsed(offset: now.scene.body.length),
      );
      _sessionStartBody = now.scene.body;
      _dirty = false;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ref = _ref;
    if (ref == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(tr(zh: '这个场景已经不在了', en: 'This scene no longer exists')),
        ),
      );
    }

    final scenes = _allScenes();
    final index = scenes.indexWhere((s) => s.scene.id == ref.scene.id);
    final words = countWords(_controller.text);
    final session = words - countWords(_sessionStartBody);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLowest,
        titleSpacing: 0,
        title: InkWell(
          onTap: _renameScene,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ref.scene.displayTitle(ref.sceneIndex),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  ref.chapter.displayTitle(ref.chapterIndex),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: sceneStatusLabel(ref.scene.status),
            onPressed: _pickStatus,
            icon: StatusDot(status: ref.scene.status, size: 14),
          ),
          IconButton(
            tooltip: tr(zh: '版本历史', en: 'Version history'),
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            scrollController: _scroll,
            maxLines: null,
            expands: true,
            autocorrect: true,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            cursorColor: cs.primary,
            style: TextStyle(
              fontSize: 17.5,
              height: 1.62,
              color: cs.onSurface,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: 24),
              hintText: tr(
                zh: '从这里开始写。\n\n加粗用 **两个星号**,斜体用 *一个*,小标题用 # 开头。',
                en: 'Start writing here.\n\n**Two asterisks** for bold, *one* for '
                    'italic, a leading # for a heading.',
              ),
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                height: 1.62,
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _EditorBar(
        words: words,
        session: session,
        canPrev: index > 0,
        canNext: index >= 0 && index < scenes.length - 1,
        onPrev: index > 0 ? () => _goTo(scenes[index - 1]) : null,
        onNext: index >= 0 && index < scenes.length - 1
            ? () => _goTo(scenes[index + 1])
            : null,
        onFormat: (kind) {
          switch (kind) {
            case _Fmt.bold:
              _apply(MarkdownEdits.wrap(_controller.value, '**'));
            case _Fmt.italic:
              _apply(MarkdownEdits.wrap(_controller.value, '*'));
            case _Fmt.heading:
              _apply(MarkdownEdits.linePrefix(_controller.value, '# '));
            case _Fmt.quote:
              _apply(MarkdownEdits.linePrefix(_controller.value, '> '));
            case _Fmt.sceneBreak:
              _apply(MarkdownEdits.insert(_controller.value, '\n\n* * *\n\n'));
          }
          HapticFeedback.selectionClick();
        },
        onDismissKeyboard: () => _focus.unfocus(),
      ),
    );
  }
}

enum _Fmt { bold, italic, heading, quote, sceneBreak }

/// The bar that is always under the writer's thumb: formatting on the left,
/// the live count in the middle, scene navigation on the right. It sits in the
/// scaffold's bottom slot, so the keyboard pushes it up instead of covering it.
class _EditorBar extends StatelessWidget {
  const _EditorBar({
    required this.words,
    required this.session,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
    required this.onFormat,
    required this.onDismissKeyboard,
  });

  final int words;
  final int session;
  final bool canPrev;
  final bool canNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final void Function(_Fmt) onFormat;
  final VoidCallback onDismissKeyboard;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Material(
      color: cs.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 4),
              _BarButton(
                icon: Icons.format_bold,
                tip: tr(zh: '加粗', en: 'Bold'),
                onTap: () => onFormat(_Fmt.bold),
              ),
              _BarButton(
                icon: Icons.format_italic,
                tip: tr(zh: '斜体', en: 'Italic'),
                onTap: () => onFormat(_Fmt.italic),
              ),
              _BarButton(
                icon: Icons.title,
                tip: tr(zh: '小标题', en: 'Heading'),
                onTap: () => onFormat(_Fmt.heading),
              ),
              _BarButton(
                icon: Icons.format_quote,
                tip: tr(zh: '引用', en: 'Quote'),
                onTap: () => onFormat(_Fmt.quote),
              ),
              _BarButton(
                icon: Icons.more_horiz,
                tip: tr(zh: '分隔符', en: 'Scene break'),
                onTap: () => onFormat(_Fmt.sceneBreak),
              ),
              Expanded(
                child: Center(
                  child: FittedBox(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          wordsLabel(words),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        if (session != 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            session > 0 ? '+${groupedCount(session)}' : groupedCount(session),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: session > 0 ? cs.primary : cs.error,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (keyboardUp)
                _BarButton(
                  icon: Icons.keyboard_hide_outlined,
                  tip: tr(zh: '收起键盘', en: 'Hide keyboard'),
                  onTap: onDismissKeyboard,
                )
              else ...[
                _BarButton(
                  icon: Icons.chevron_left,
                  tip: tr(zh: '上一场景', en: 'Previous scene'),
                  onTap: canPrev ? onPrev : null,
                ),
                _BarButton(
                  icon: Icons.chevron_right,
                  tip: tr(zh: '下一场景', en: 'Next scene'),
                  onTap: canNext ? onNext : null,
                ),
              ],
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.tip, this.onTap});

  final IconData icon;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        size: 21,
        color: onTap == null
            ? cs.onSurfaceVariant.withValues(alpha: 0.35)
            : cs.onSurface,
      ),
    );
  }
}
