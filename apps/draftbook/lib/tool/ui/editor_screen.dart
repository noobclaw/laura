import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/review_prompt.dart';
import '../models.dart';
import '../app_theme.dart';
import '../haptics.dart';
import '../store.dart';
import 'glyphs.dart';
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
    this.focusOnOpen = false,
  });

  final DraftbookStore store;
  final String projectId;
  final String sceneId;

  /// "Keep writing": open with the keyboard up and the caret where the writer
  /// left it. Opening a scene from the outline is reading first, so it does not.
  final bool focusOnOpen;

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
  int _sessionStartWords = 0;
  bool _dirty = false;

  /// The last text the listener saw. The controller also notifies on caret
  /// moves and on programmatic assignments; only a real text change may start
  /// the autosave clock or take a version.
  String _lastText = '';

  /// Whether this session's opening text has been kept as a version. Once per
  /// session, not once per autosave — `_dirty` resets after every save.
  bool _sessionSnapshotted = false;

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
    widget.store.addListener(_onStore);
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
    widget.store.removeListener(_onStore);
    _noteCaret();
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
    _sessionStartWords = ref.scene.words;
    _sessionSnapshotted = false;
    _lastText = ref.scene.body;
    final body = ref.scene.body;
    _controller.value = TextEditingValue(
      text: body,
      selection: TextSelection.collapsed(offset: (ref.scene.caret ?? body.length).clamp(0, body.length)),
    );
    _dirty = false;
    widget.store.noteSceneOpened(p, ref.scene);
    if (focus && (widget.focusOnOpen || body.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  /// Where the caret is now, kept on the scene being left.
  void _noteCaret() {
    final ref = _ref;
    final sel = _controller.selection;
    if (ref == null || !sel.isValid) return;
    widget.store.noteCaret(ref.scene, sel.extentOffset);
  }

  /// Takes a body that changed underneath the editor (a restore, or an Undo of
  /// one, landed while this screen was open or covered). The session restarts
  /// from it: that is not writing, so it must not count towards the rating
  /// prompt or be snapshotted again. `_lastText` is set before the controller
  /// so the listener does not read the assignment as an edit and spend a
  /// history slot on it.
  void _adopt(Scene scene) {
    final body = scene.body;
    final at = _controller.selection.isValid ? _controller.selection.extentOffset : body.length;
    _lastText = body;
    _controller.value = TextEditingValue(
      text: body,
      selection: TextSelection.collapsed(offset: at.clamp(0, body.length)),
    );
    _sessionStartBody = body;
    _sessionStartWords = scene.words;
    _sessionSnapshotted = false;
    _dirty = false;
  }

  /// Store changes made elsewhere — history's Undo bar outlives the history
  /// screen by up to six seconds — reach the page here. Unsaved typing wins:
  /// while the editor is dirty the store is about to be overwritten anyway.
  void _onStore() {
    if (_dirty || !mounted) return;
    final ref = _ref;
    if (ref == null || ref.scene.body == _controller.text) return;
    setState(() => _adopt(ref.scene));
  }

  void _onChanged() {
    // Caret moves and selection changes notify too; they are not edits.
    if (_controller.text == _lastText) return;
    _lastText = _controller.text;
    if (!_sessionSnapshotted) {
      // First change of this session, and `scene.body` is still the text the
      // session started with — keep it. Without this, a scene written in one
      // sitting has no recovery point at all: select-all + one keystroke would
      // overwrite it, and the only version ever taken (on leaving) would be
      // the damage. Once per session: keying this off `_dirty` (which every
      // autosave resets) took a version at every typing pause and filled the
      // 20 slots within minutes.
      _sessionSnapshotted = true;
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
    // This path already waited out its own debounce; do not stack the store's.
    widget.store.saveNow();
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
    _noteCaret();
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
                hintText: tr(zh: '例如：雨夜的电话', en: 'e.g. The call at midnight'),
              ),
            ),
            const SizedBox(height: DbSpace.x1_5),
            TextField(
              controller: synopsisCtl,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr(zh: '梗概（只给自己看）', en: 'Synopsis (for your eyes)'),
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
    disposeNextFrame([titleCtl, synopsisCtl]);
  }

  Future<void> _pickStatus() async {
    final p = _project;
    final ref = _ref;
    if (p == null || ref == null) return;
    final chosen = await showModalBottomSheet<SceneStatus>(
      context: context,
      sheetAnimationStyle: DbMotion.sheetStyle(context),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(DbSpace.gutter, 0, DbSpace.gutter, DbSpace.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHeading(title: tr(zh: '这一场景写到哪了', en: 'Where this scene stands')),
              const SizedBox(height: DbSpace.x1),
              for (final s in SceneStatus.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: StatusMark(status: s, size: 18),
                  title: Text(sceneStatusLabel(s)),
                  selected: ref.scene.status == s,
                  trailing: ref.scene.status == s
                      ? Icon(Icons.check, size: 20, color: DbColors.of(ctx).accent)
                      : null,
                  onTap: () => Navigator.pop(ctx, s),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) {
      Haptics.select();
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
    if (now.scene.body != _controller.text) _adopt(now.scene);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final ref = _ref;
    if (ref == null) {
      // Deleted from another screen while this one was underneath: say what
      // happened and give the way out, instead of an empty page.
      return Scaffold(
        backgroundColor: c.paper,
        appBar: AppBar(),
        body: Padding(
          padding: const EdgeInsets.all(DbSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(zh: '这个场景已经不在了', en: 'This scene no longer exists'),
                style: DbType.heading.copyWith(color: c.ink),
              ),
              const SizedBox(height: DbSpace.x1),
              Text(
                tr(
                  zh: '它在别处被删掉了。它最后保存的正文和版本都随它一起删除；'
                      '如果刚删，回到大纲还能点「撤销」。',
                  en: 'It was deleted elsewhere, with its text and versions. If '
                      'that just happened, Undo is still on the outline.',
                ),
                style: DbType.body.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: DbSpace.x3),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(tr(zh: '回到大纲', en: 'Back to the outline')),
              ),
            ],
          ),
        ),
      );
    }

    final scenes = _allScenes();
    final index = scenes.indexWhere((s) => s.scene.id == ref.scene.id);
    final words = countWords(_controller.text);
    final session = words - _sessionStartWords;

    return Scaffold(
      backgroundColor: c.page,
      appBar: AppBar(
        backgroundColor: c.page,
        titleSpacing: 0,
        title: Semantics(
          button: true,
          hint: tr(zh: '编辑标题与梗概', en: 'Edit title and synopsis'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _renameScene,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DbSpace.x1, vertical: DbSpace.x0_5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ref.scene.displayTitle(ref.sceneIndex),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DbType.rowTitle.copyWith(color: c.ink),
                  ),
                  // The chapter, then the live count: the byline of the page
                  // being set. It lives up here so the bar under the thumb
                  // has room for 8pt between its keys (kb F7).
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: ref.chapter.displayTitle(ref.chapterIndex)),
                      TextSpan(
                        text: '  ${wordsLabel(words)}',
                        style: const TextStyle(fontStyle: FontStyle.normal, fontFeatures: DbType.tabular),
                      ),
                      if (session != 0)
                        TextSpan(
                          text: session > 0 ? '  +${groupedCount(session)}' : '  ${groupedCount(session)}',
                          style: TextStyle(
                            fontStyle: FontStyle.normal,
                            fontFeatures: DbType.tabular,
                            color: session > 0 ? c.accent : c.signal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DbType.bylineSmall.copyWith(color: c.inkMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          Tooltip(
            message: sceneStatusLabel(ref.scene.status),
            child: Semantics(
              button: true,
              label: tr(
                zh: '状态：${sceneStatusLabel(ref.scene.status)}',
                en: 'Status: ${sceneStatusLabel(ref.scene.status)}',
              ),
              excludeSemantics: true,
              child: PressScale(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _pickStatus,
                  // Mark and word together: the state never rides on the
                  // mark's shape alone.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: DbSpace.iconButton),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: DbSpace.x1_5, vertical: DbSpace.x1),
                        decoration: BoxDecoration(
                          borderRadius: DbRadius.pillAll,
                          border: Border.all(color: c.ruleStrong, width: DbRadius.hairline),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ExcludeSemantics(child: StatusMark(status: ref.scene.status, size: 12)),
                            const SizedBox(width: DbSpace.x1),
                            Text(sceneStatusLabel(ref.scene.status),
                                style: DbType.meta.copyWith(color: c.ink)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          DbIconButton(
            glyph: DbGlyph.history,
            tooltip: tr(zh: '版本历史', en: 'Version history'),
            onPressed: _openHistory,
          ),
          const SizedBox(width: DbSpace.x0_5),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(DbSpace.gutter + DbSpace.x0_5, DbSpace.x1, DbSpace.gutter, 0),
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
            cursorColor: c.accent,
            cursorWidth: 2,
            style: DbType.manuscript.copyWith(color: c.ink),
            decoration: InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: DbSpace.x3),
              hintText: tr(
                zh: '从这里开始写。\n\n加粗用 **两个星号**，斜体用 *一个*，小标题用 # 开头。',
                en: 'Start writing here.\n\n**Two asterisks** for bold, *one* for '
                    'italic, a leading # for a heading.',
              ),
              hintStyle: DbType.italic(DbType.manuscript).copyWith(color: c.inkMuted),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _EditorBar(
        onPrev: index > 0 ? () => _goTo(scenes[index - 1]) : null,
        onNext: index >= 0 && index < scenes.length - 1 ? () => _goTo(scenes[index + 1]) : null,
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
          Haptics.select();
        },
        onDismissKeyboard: () => _focus.unfocus(),
      ),
    );
  }
}

enum _Fmt { bold, italic, heading, quote, sceneBreak }

/// The bar that is always under the writer's thumb: formatting on the left,
/// scene navigation (or, with the keyboard up, the key that lowers it) on the
/// right, 8pt between keys (kb F7). The live count is in the app bar. It sits in the
/// scaffold's bottom slot, so the keyboard pushes it up instead of covering it
/// (PLAN.md 交互铁律 1). The format keys are type, not icons: B, I, H, a quote
/// and the typesetter's asterism.
class _EditorBar extends StatelessWidget {
  const _EditorBar({
    required this.onPrev,
    required this.onNext,
    required this.onFormat,
    required this.onDismissKeyboard,
  });

  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final void Function(_Fmt) onFormat;
  final VoidCallback onDismissKeyboard;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final face = DbType.glyph.copyWith(color: c.ink);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(top: BorderSide(color: c.rule, width: DbRadius.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DbSpace.bar),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DbSpace.x1),
            child: Row(
              children: [
                ..._spaced([
                  _Key(
                    tip: tr(zh: '加粗', en: 'Bold'),
                    onTap: () => onFormat(_Fmt.bold),
                    child: Text('B', style: face),
                  ),
                  _Key(
                    tip: tr(zh: '斜体', en: 'Italic'),
                    onTap: () => onFormat(_Fmt.italic),
                    child: Text('I', style: face.copyWith(fontStyle: FontStyle.italic, fontWeight: FontWeight.w400)),
                  ),
                  _Key(
                    tip: tr(zh: '小标题', en: 'Heading'),
                    onTap: () => onFormat(_Fmt.heading),
                    child: Text('H', style: face),
                  ),
                  _Key(
                    tip: tr(zh: '引用', en: 'Quote'),
                    onTap: () => onFormat(_Fmt.quote),
                    child: DbIcon(DbGlyph.quote, size: 18, color: c.ink),
                  ),
                  _Key(
                    tip: tr(zh: '分隔符', en: 'Scene break'),
                    onTap: () => onFormat(_Fmt.sceneBreak),
                    child: DbIcon(DbGlyph.asterism, size: 22, color: c.ink),
                  ),
                ]),
                const Spacer(),
                if (keyboardUp)
                  _Key(
                    tip: tr(zh: '收起键盘', en: 'Hide keyboard'),
                    onTap: onDismissKeyboard,
                    child: DbIcon(DbGlyph.keyboardDown, size: 22, color: c.ink),
                  )
                else
                  ..._spaced([
                    _Key(
                      tip: tr(zh: '上一场景', en: 'Previous scene'),
                      onTap: onPrev,
                      child: DbIcon(DbGlyph.prev, size: 22, color: onPrev == null ? c.ruleStrong : c.ink),
                    ),
                    _Key(
                      tip: tr(zh: '下一场景', en: 'Next scene'),
                      onTap: onNext,
                      child: DbIcon(DbGlyph.next, size: 22, color: onNext == null ? c.ruleStrong : c.ink),
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [keys] with 8pt between neighbours.
  static List<Widget> _spaced(List<Widget> keys) => [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: DbSpace.x1),
          keys[i],
        ],
      ];
}

/// One key of the editor bar: 44 wide, 48 tall, pressed on touch-down.
class _Key extends StatelessWidget {
  const _Key({required this.tip, required this.onTap, required this.child});

  final String tip;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: tip,
        excludeSemantics: true,
        child: PressScale(
          enabled: onTap != null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: DbSpace.tap,
              height: DbSpace.iconButton,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
